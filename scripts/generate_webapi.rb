#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'yaml'
require_relative './lib/visitors'
require_relative './lib/helpers'

# https://github.com/slack-edge/slack-web-api-client/blob/4d1d93df8abe423ea7ee3b18591cd83d9bcfe6e6/scripts/code_generator.rb#L91-L115
# RTM API is legacy so not going to support it
UNSUPPORTED_METHODS = [
  /admin\.analytics\.getFile/,
  /api\.test/,
  /oauth\.access/,
  /oauth\.token/,
  /files\.comments\./,
  /dialog\./,
  /calls\./,
  /workflows\./,
  /channels\./,
  /groups\./,
  /mpim\./,
  /im\./,
  /rtm\./
]

# Reviewed reference-only methods whose response examples replace the minimal
# success fallback. Keep this explicit until other reference-only APIs are reviewed.
REFERENCE_RESPONSE_METHODS = %w[
  admin.apps.permissions.remove
  admin.apps.permissions.set
].freeze

def reference_response_samples(method_name, api_ref)
  examples = api_ref.dig('response', 'examples')
  return [{ 'ok' => true }] if examples == []
  return unless REFERENCE_RESPONSE_METHODS.include?(method_name)

  raise "Missing response examples for #{method_name}" unless examples.is_a?(Array) && !examples.empty?

  examples.map do |example|
    response = JSON.parse(example)
    raise "Invalid response object for #{method_name}" unless response.is_a?(Hash) && [true, false].include?(response['ok'])

    response
  end
end

api_ref_dir = './vendor/slack-api-ref/methods/'
api_ref_paths = Dir.glob("#{api_ref_dir}/**/*.json").sort

json_logs = './vendor/java-slack-sdk/json-logs'
api_dir = "#{json_logs}/samples/api/"
sample_json_paths = Dir.glob("#{api_dir}*.json").sort

output_dir = './.tmp/WebAPI'
FileUtils.mkdir_p(File.join(output_dir, 'schemas'))

def main(api_ref_paths, sample_json_paths, output_dir)
  openapi = JSON.parse(File.read(File.join(__dir__, 'lib/base_openapi.json')))

  # Generate schemas by quicktype
  process_in_queue(sample_json_paths) do |path|
    generate_openapi_component(path, File.join(output_dir, 'schemas'))
  end

  # Use reviewed reference examples when Java fixtures are unavailable. Explicit
  # empty example lists retain the existing minimal success-envelope fallback.
  fallback_responses_dir = File.join(output_dir, 'fallback-responses')
  api_ref_paths.each do |path|
    method_name = File.basename(path, '.json')
    next if sample_json_paths.any? { File.basename(_1, '.json') == method_name }

    api_ref = JSON.parse(File.read(path))
    responses = reference_response_samples(method_name, api_ref)
    next unless responses

    FileUtils.mkdir_p(fallback_responses_dir)
    fallback_response_path = File.join(fallback_responses_dir, "#{method_name}.json")
    response_paths = responses.each_with_index.map do |response, index|
      sample_path = "#{fallback_response_path}.#{index}.json"
      File.write(sample_path, JSON.generate(response))
      sample_path
    end
    generate_openapi_component(fallback_response_path, File.join(output_dir, 'schemas'), response_paths)
  end

  # Load generated schemas and put them in #components/schemas section
  schema_paths = Dir.glob("#{output_dir}/schemas/*.json").sort
  schema_paths.each do |path|
    json = JSON.parse(File.read(path))
    openapi['components']['schemas'].merge!(json['definitions'])
  end

  # Generate paths
  paths = {}
  api_ref_paths.each do |path|
    # Methods need a fixture, reviewed reference examples, or an explicit empty response.
    method_name = File.basename(path, '.json')
    unless schema_paths.any? { File.basename(_1, '.json') == method_name }
      puts "Skip, this method doesn't have response schema #{method_name}"
      next
    end

    result = generate_openapi_path(path)
    paths.merge!(result) if result
  end
  openapi['paths'] = paths

  remove_orphan_schemas(openapi)

  # Output openapi_yaml
  File.write(File.join(output_dir, 'openapi.json'), JSON.pretty_generate(openapi))
end

def generate_openapi_component(path, output_dir, sample_paths = nil)
  method_name = File.basename(path, '.json')
  return puts "Skip, this method isn't supported #{method_name}" if UNSUPPORTED_METHODS.include?(method_name)

  model_name = "#{method_name.split('.').map { _1.sub(/\A./, &:upcase) }.join}Response"
  output_path = File.join(output_dir, "#{method_name}.json")

  if File.exist?(output_path)
    puts "Found #{path} exists. Skip generating schema."
    json = JSON.parse(File.read(output_path))
  else
    json = generate_json_schema(sample_paths || path, output_path, model_name)
  end

  # fix json
  visitors = [
    InvalidKeysRemover.new,
    ReferenceFixer.new,
    AcronymsFixer.new('DND' => 'Dnd', 'MCP' => 'Mcp'),
    TypeFixer.new,
    UserProfileRefFixer.new,
    TeamProfileRefFixer.new,
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

def generate_openapi_path(path)
  method_name = File.basename(path, '.json')
  return puts "Skip this method isn't supported #{method_name}" if UNSUPPORTED_METHODS.any? { _1.match(method_name) }

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

  response_model_name = "#{method_name.split('.').map { _1.sub(/\A./, &:upcase) }.join}Response"
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

main(api_ref_paths, sample_json_paths, output_dir) if $PROGRAM_NAME == __FILE__
