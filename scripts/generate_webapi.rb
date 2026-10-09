#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'yaml'
require_relative './lib/visitors'
require_relative './lib/helpers'

# Repository sources are UTF-8; do not depend on the caller's locale.
Encoding.default_external = Encoding::UTF_8

# Based on the exclusion list in slack-web-api-client:
# https://github.com/slack-edge/slack-web-api-client/blob/649fb67cc970fe04f05ea3fb215180bd698cee97/scripts/code_generator.rb#L91-L115
# Patterns are anchored to the start of the method name, as in the reference,
# so current APIs such as usergroups.* and admin.workflows.* stay generated.
# Unlike the reference, calls.* and workflows.* are generated because they are
# current APIs. That list only selects which Java fixtures become response types
# and has not changed since its 2023 v0.1.x releases; slack-web-api-client's
# hand-written API surface now exposes calls.* and workflows.* as well. The
# retired Steps from Apps methods (workflows.stepCompleted, workflows.stepFailed,
# workflows.updateStep) still have Java fixtures but are not generated because
# slack-api-ref no longer lists them.
UNSUPPORTED_METHODS = [
  # Legacy APIs superseded by current Slack APIs
  /\Achannels\./,       # Replaced by conversations.*
  /\Agroups\./,         # Replaced by conversations.*
  /\Aim\./,             # Replaced by conversations.*
  /\Ampim\./,           # Replaced by conversations.*
  /\Artm\./,            # RTM API is legacy; use the Events API or Socket Mode
  /\Adialog\./,         # Dialogs are legacy; replaced by modals (views.*)
  /\Afiles\.comments\./, # File comments are legacy
  /\Aoauth\.access\z/,  # Classic app OAuth; replaced by oauth.v2.access
  /\Aoauth\.token\z/,   # Retired workspace apps; replaced by oauth.v2.access

  # Responses the generator cannot represent
  /\Aadmin\.analytics\.getFile\z/, # Returns a gzip-compressed file, not a JSON body
].freeze

def unsupported_method?(method_name)
  UNSUPPORTED_METHODS.any? { _1.match?(method_name) }
end

# Data-quality warnings are printed as they happen and, on GitHub Actions,
# reported once at the end because Actions shows at most 10 warning
# annotations per step.
GENERATOR_WARNINGS = []

def generator_warning(message)
  GENERATOR_WARNINGS << message
  warn message
end

def report_generator_warnings(warnings = GENERATOR_WARNINGS, env: ENV, io: $stdout)
  return if warnings.empty? || env['GITHUB_ACTIONS'] != 'true'

  title = "Web API generation: #{warnings.size} warning(s)"
  body = warnings.join("\n").gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
  io.puts "::warning title=#{title}::#{body}"

  summary_path = env['GITHUB_STEP_SUMMARY']
  return unless summary_path

  File.open(summary_path, 'a') do |file|
    file.puts "### #{title}", ''
    warnings.each { file.puts "- #{_1}" }
    file.puts
  end
end

api_ref_dir = './vendor/slack-api-ref/methods/'
api_ref_paths = Dir.glob("#{api_ref_dir}/**/*.json").sort

json_logs = './vendor/java-slack-sdk/json-logs'
api_dir = "#{json_logs}/samples/api/"
sample_json_paths = Dir.glob("#{api_dir}*.json").sort

output_dir = './.tmp/WebAPI'
FileUtils.mkdir_p(File.join(output_dir, 'schemas'))

# Properties is the same ConversationProperties model across conversation fixtures.
# Union its fields before replacing the definition; future fixture-only fields must
# survive too. Keep the existing last-definition policy for overlapping fields and
# other names: quicktype also reuses names for unrelated models (e.g. AgentSession),
# which require semantic ref fixers rather than a blanket object union.
def merge_response_schemas!(schemas, incoming)
  previous = schemas['Properties']
  current = incoming['Properties']
  if previous && current
    unless [previous, current].all? { _1['type'] == 'object' && _1['properties'].is_a?(Hash) }
      raise 'Cannot merge conversation Properties: expected object schemas'
    end
    incoming = incoming.merge('Properties' => current.merge(
      'properties' => previous['properties'].merge(current['properties'])
    ))
  end
  schemas.merge!(incoming)
end

def main(api_ref_paths, sample_json_paths, output_dir)
  openapi = JSON.parse(File.read(File.join(__dir__, 'lib/base_openapi.json')))

  # Generate schemas by quicktype
  process_in_queue(sample_json_paths) do |path|
    generate_openapi_component(path, File.join(output_dir, 'schemas'))
  end

  # Load generated schemas and put them in #components/schemas section.
  # quicktype may normalize the requested top-level name (e.g. ApiTest -> APITest),
  # so operations reference the name recorded in each generated schema.
  schema_paths = Dir.glob("#{output_dir}/schemas/*.json").sort
  response_model_names = {}
  schema_paths.each do |path|
    json = JSON.parse(File.read(path))
    merge_response_schemas!(openapi['components']['schemas'], json['definitions'])
    response_model_names[File.basename(path, '.json')] = json['$ref'].split('/').last
  end

  # Generate paths
  paths = {}
  api_ref_paths.each do |path|
    method_name = File.basename(path, '.json')
    if unsupported_method?(method_name)
      puts "Skip, this method isn't supported #{method_name}"
      next
    end

    # Like java-slack-sdk, only methods with a recorded response fixture are
    # generated; slack-api-ref documentation examples are not used for types.
    unless response_model_names.key?(method_name)
      generator_warning "Skip #{method_name}: no java-slack-sdk fixture"
      next
    end

    result = generate_openapi_path(path, response_model_names[method_name])
    paths.merge!(result) if result
  end
  openapi['paths'] = paths

  remove_orphan_schemas(openapi)

  # Output openapi_yaml
  File.write(File.join(output_dir, 'openapi.json'), JSON.pretty_generate(openapi))
end

def generate_openapi_component(path, output_dir)
  method_name = File.basename(path, '.json')
  model_name = "#{method_name.split('.').map { _1.sub(/\A./, &:upcase) }.join}Response"
  output_path = File.join(output_dir, "#{method_name}.json")

  if File.exist?(output_path)
    puts "Found #{path} exists. Skip generating schema."
    json = JSON.parse(File.read(output_path))
  else
    json = generate_json_schema(path, output_path, model_name)
  end

  # fix json
  visitors = [
    InvalidKeysRemover.new,
    ReferenceFixer.new,
    AcronymsFixer.new('DND' => 'Dnd', 'MCP' => 'Mcp'),
    TypeFixer.new,
    UserProfileRefFixer.new,
    TeamProfileRefFixer.new,
    CallRefFixer.new,
    ConversationPropertiesRefFixer.new,
    APITestArgsRefFixer.new,
    AppWorkflowRefFixer.new,
    UsergroupRefFixer.new,
    ResponseMetadataRefFixer.new,
    WorkflowCollaboratorErrorRefFixer.new,
    OptionalityFixer.new,
    ItemTsOptionalAdder.new,
  ]
  visitors.each do |visitor|
    visitor.walk(json)
  end

  File.write(output_path, JSON.pretty_generate(json))
  output_path
end

# slack-api-ref misses many properties' type
# They need to be filled in
def normalize_type(name, attributes)
  attributes = {} unless attributes.is_a?(Hash)

  return 'string' if attributes['type'] == 'enum'
  return 'object' if attributes['format'] == 'json'
  return 'string' if attributes['type'] == 'timestamp'

  # apps.manifest.create requires 'manifest' property as json but the slack-api-ref describes it wrong type
  return 'string' if attributes['type'] == 'manifest object as string'
  # bots.info requires `bot` property but wrong type is set
  return 'string' if attributes['type'] == 'user'
  # chat.delete describes 'channel' prop wrong
  return 'string' if attributes['type'] == 'channel'
  # files.delete ...
  return 'string' if attributes['type'] == 'file'

  if attributes['type'].nil?
    case attributes['example']
    when String
      return 'string'
    when Numeric
      return 'number'
    else
      return 'string'
    end
  end

  attributes['type']
end

def generate_openapi_path(path, response_model_name)
  method_name = File.basename(path, '.json')
  json = JSON.parse(File.read(path))
  operation_id = method_name.camelize(separator: '\.')
  method_args = json['args'].is_a?(Hash) ? json['args'] : {}
  required = []
  request_body_props = method_args.each_with_object({}) do |(name, attributes), props|
    attributes = {} unless attributes.is_a?(Hash)
    required.append(name) if attributes['required']

    case name
    when 'view'
      props['view'] = { '$ref': '#/components/schemas/View' }
    when 'block'
      props['block'] = { '$ref': '#/components/schemas/Block' }
    when 'blocks'
      props['blocks'] = { 'type': 'array', 'items': { '$ref': '#/components/schemas/Block' } }
    when 'attachments'
      props['attachments'] = { 'type': 'array', 'items': { '$ref': '#/components/schemas/Attachment' } }
    when 'ts'
      props['ts'] = { 'type': 'string' }
    when 'image'
      props['image'] = { 'type': 'string', 'format': 'binary' }
    else
      normalized_type = normalize_type(name, attributes)
      props[name] = { 'type': normalized_type }
    end

    props[name]['example'] = attributes['example'] if attributes.key?('example')
    props[name]['description'] = attributes['desc'] if attributes.key?('desc')
  end

  content_type = request_body_props.any? { |_, v| v['format'] == 'binary' } ? 'multipart/form-data' : 'application/json'
  content_schema = if request_body_props.empty?
                     { 'type': 'object', 'additionalProperties': false }
                   else
                     { 'type': 'object', 'properties': request_body_props, 'required': required }
                   end
  request_body = {
    'required': !request_body_props.empty?,
    'content': {
      "#{content_type}": {
        'schema': content_schema
      }
    }
  }

  base = {
    "#{method_name}": {
      # Slack seems accapt POST always
      'post': {
        'tags': [method_name.split('.').first.capitalize],
        'operationId': operation_id,
        'summary': json['desc'],
        'requestBody': request_body,
        'responses': {
          '200': {
            'description': 'OK',
            'content': {
              'application/json': {
                'schema': {
                  '$ref': "#/components/schemas/#{response_model_name}"
                }
              }
            }
          }
        }
      }
    }
  }

  base
end

def remove_orphan_schemas(openapi)
  loop do
    defined = openapi['components']['schemas'].keys
    referenced = openapi.to_json.scan(%r{"#/components/schemas/([^"]+)"}).flatten.uniq
    orphans = defined - referenced
    break if orphans.empty?

    orphans.each do |orphan|
      openapi['components']['schemas'].delete(orphan)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  main(api_ref_paths, sample_json_paths, output_dir)
  report_generator_warnings
end
