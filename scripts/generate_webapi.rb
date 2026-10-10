#!/usr/bin/env ruby

# Builds .tmp/WebAPI/openapi.json and the swift-openapi-generator configs for the Web API and events.
#
#   * Paths and request bodies come from the upstream slack-api-ref method docs.
#   * Response schemas and event schemas come from the upstream java-slack-sdk Java classes
#     (scripts/lib/java_openapi.rb), with the explicit exceptions in scripts/java_type_overrides.yml.
#   * Only methods and events with an upstream java-slack-sdk fixture are generated, so every generated type
#     is checked against a recorded payload (scripts/check_fixtures.rb).

require 'fileutils'
require 'json'
require 'yaml'
require_relative './lib/helpers'
require_relative './lib/java_openapi'

# Repository sources are UTF-8; do not depend on the caller's locale.
Encoding.default_external = Encoding::UTF_8

ROOT_DIR = File.expand_path('..', __dir__)
SDK_DIR = File.join(ROOT_DIR, 'vendor/java-slack-sdk')
TYPE_OVERRIDES_PATH = File.join(__dir__, 'java_type_overrides.yml')
HANDWRITTEN_SCHEMAS_PATH = File.join(__dir__, 'handwritten_schemas.yml')
BLOCK_KIT_DIR = File.join(ROOT_DIR, 'Sources/SlackBlockKit')

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

# Events with an upstream fixture that are not generated.
UNSUPPORTED_EVENTS = [
  /\AResources/,          # Retired workspace apps (resources_added, resources_removed)
  /\AUserResource/,       # Retired workspace apps (user_resource_*)
  /\AFileComment(Added|Edited)\z/, # File comments are legacy
].freeze

# Event schema names whose spelling differs from the fixture name, kept for source compatibility.
EVENT_SCHEMA_NAMES = {
  'ChannelIdChanged' => 'ChannelIDChangedEvent',
  'ImClose' => 'IMCloseEvent',
  'ImCreated' => 'IMCreatedEvent',
  'ImHistoryChanged' => 'IMHistoryChangedEvent',
  'ImOpen' => 'IMOpenEvent',
}.freeze

def unsupported_method?(method_name)
  UNSUPPORTED_METHODS.any? { _1.match?(method_name) }
end

def unsupported_event?(event_name)
  UNSUPPORTED_EVENTS.any? { _1.match?(event_name) }
end

# `ImClosePayload.json` => "ImClose"
def event_name_from_fixture(path)
  File.basename(path, '.json').delete_suffix('Payload')
end

def event_schema_name(event_name)
  EVENT_SCHEMA_NAMES.fetch(event_name) { "#{event_name}Event" }
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

# Builds the OpenAPI document. `methods_with_fixtures` and `event_fixture_paths` select what is generated.
# `check_unused` fails on entries of java_type_overrides.yml and handwritten_schemas.yml that nothing used,
# which is only meaningful for a full generation.
def build_openapi(api_ref_paths, methods_with_fixtures, event_fixture_paths, sdk_dir: SDK_DIR, check_unused: false)
  index = JavaOpenAPI.load_index(sdk_dir)
  GsonAdapters.validate!(sdk_dir)
  type_overrides = TypeOverrides.load(TYPE_OVERRIDES_PATH)
  type_overrides.validate!(index)
  builder = SchemaBuilder.new(index, type_overrides: type_overrides,
                                     handwritten_schemas: YAML.safe_load_file(HANDWRITTEN_SCHEMAS_PATH),
                                     block_kit_types: JavaOpenAPI.swift_public_types(BLOCK_KIT_DIR))

  openapi = JSON.parse(File.read(File.join(__dir__, 'lib/base_openapi.json')))
  openapi['paths'] = build_paths(api_ref_paths, methods_with_fixtures, index, builder)
  add_events(openapi, event_fixture_paths, index, builder)
  check_unused_entries(type_overrides, builder) if check_unused

  openapi['components']['schemas'] = builder.components
  [openapi, builder]
end

def check_unused_entries(type_overrides, builder)
  unused_overrides = type_overrides.unused_keys
  raise "unused entries in java_type_overrides.yml: #{unused_overrides.join(', ')}" unless unused_overrides.empty?

  unused_schemas = builder.unused_handwritten_schemas
  raise "unreferenced schemas in handwritten_schemas.yml: #{unused_schemas.join(', ')}" unless unused_schemas.empty?
end

# One path per supported slack-api-ref method that has a fixture; the 200 response is the Java response class.
def build_paths(api_ref_paths, methods_with_fixtures, index, builder)
  # Request bodies refer to these shared schemas.
  builder.shared_ref(index.fully_qualified('com.slack.api.model.Attachment'))
  builder.map_to_swift('Block', 'SlackBlockKit.Block', 'SlackBlockKit')
  builder.map_to_swift('View', 'SlackBlockKit.View', 'SlackBlockKit')

  api_ref_paths.each_with_object({}) do |path, paths|
    method_name = File.basename(path, '.json')
    if unsupported_method?(method_name)
      puts "Skip, this method isn't supported #{method_name}"
      next
    end

    # Only methods with a recorded java-slack-sdk response fixture are generated;
    # slack-api-ref documentation examples are not used for types.
    unless methods_with_fixtures.include?(method_name)
      generator_warning "Skip #{method_name}: no java-slack-sdk fixture"
      next
    end

    schema_name = JavaOpenAPI.response_schema_name(method_name)
    builder.add_root(schema_name, JavaOpenAPI.response_class(index, method_name), required: ['ok'])
    paths.merge!(JSON.parse(JSON.generate(generate_openapi_path(path, schema_name))))
  end
end

# Adds each event with a fixture as a schema marked with its Slack `type` (and message `subtype`).
def add_events(openapi, event_fixture_paths, index, builder)
  events = {}
  event_fixture_paths.each do |path|
    event_name = event_name_from_fixture(path)
    if unsupported_event?(event_name)
      puts "Skip #{event_name}: unsupported event"
      next
    end

    java_class = JavaOpenAPI.event_class(index, event_name)
    type_name = java_class.constants['TYPE_NAME'] or raise "#{java_class.fqn} has no TYPE_NAME"
    schema_name = event_schema_name(event_name)
    builder.add_root(schema_name, java_class, required: ['type'])
    events[schema_name] = { 'type' => type_name, 'subtype' => java_class.constants['SUBTYPE_NAME'] }.compact
  end
  openapi['x-slack-events'] = events.sort.to_h
end

# swift-openapi-generator config: typeOverrides point placeholder schemas at hand-written Swift types.
def generator_config(builder, mode:, access_modifier:)
  config = {
    'generate' => [mode],
    'accessModifier' => access_modifier,
    'namingStrategy' => 'idiomatic',
  }
  imports = builder.mapped_modules.to_a.sort & %w[SlackBlockKit]
  config['additionalImports'] = imports unless imports.empty?
  config['typeOverrides'] = { 'schemas' => builder.type_mappings } unless builder.type_mappings.empty?
  config
end

def main(api_ref_paths, sample_json_paths, event_fixture_paths, output_dir)
  methods_with_fixtures = sample_json_paths.map { File.basename(_1, '.json') }.to_set
  openapi, builder = build_openapi(api_ref_paths, methods_with_fixtures, event_fixture_paths, check_unused: true)

  FileUtils.mkdir_p(output_dir)
  File.write(File.join(output_dir, 'openapi.json'), JSON.pretty_generate(openapi))
  File.write(File.join(output_dir, 'types-config.yaml'),
             generator_config(builder, mode: 'types', access_modifier: 'public').to_yaml)
  File.write(File.join(output_dir, 'client-config.yaml'),
             generator_config(builder, mode: 'client', access_modifier: 'internal').to_yaml)
  File.write(File.join(output_dir, 'generation-report.json'),
             JSON.pretty_generate(builder.report.transform_values { _1.to_a.sort }))
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

  {
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
end

if $PROGRAM_NAME == __FILE__
  api_ref_paths = Dir.glob(File.join(ROOT_DIR, 'vendor/slack-api-ref/methods/**/*.json')).sort
  sample_json_paths = Dir.glob(File.join(SDK_DIR, 'json-logs/samples/api/*.json')).sort
  event_fixture_paths = Dir.glob(File.join(SDK_DIR, 'json-logs/samples/events/*.json')).sort
  main(api_ref_paths, sample_json_paths, event_fixture_paths, File.join(ROOT_DIR, '.tmp/WebAPI'))
  report_generator_warnings
end
