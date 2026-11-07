# frozen_string_literal: true

require 'json'
require 'yaml'

# The event fixtures that select and check generated events: upstream java-slack-sdk's recorded
# json-logs/samples/events/<Name>Payload.json, plus the downstream payloads in scripts/event_fixtures/ for
# events that java-slack-sdk models but has not recorded (scripts/event_fixtures.yml).
#
# A downstream payload is a verbatim copy of the JSON that the event class's upstream unit test deserializes,
# and generation fails unless it still equals that JSON. It also fails when an entry and its payload file do
# not pair up, and when upstream records the event itself, so that the downstream copy is deleted.
module EventFixtures
  ROOT_DIR = File.expand_path('../..', __dir__)
  SDK_DIR = File.join(ROOT_DIR, 'vendor/java-slack-sdk')
  MANIFEST_PATH = File.join(ROOT_DIR, 'scripts/event_fixtures.yml')
  LOCAL_DIR = File.join(ROOT_DIR, 'scripts/event_fixtures')

  # A Java string literal, with escapes.
  JAVA_STRING = /"((?:\\.|[^"\\])*)"/
  # `String json = "..." + "...";`, the payload an upstream event test deserializes.
  JAVA_JSON_DECLARATION = /\bString\s+json\s*=\s*((?:#{JAVA_STRING.source}\s*\+?\s*)+);/m

  module_function

  # Every event fixture path, sorted by file name. Validates the downstream payloads first.
  def paths(sdk_dir: SDK_DIR, manifest_path: MANIFEST_PATH, local_dir: LOCAL_DIR)
    upstream = Dir.glob(File.join(sdk_dir, 'json-logs/samples/events/*.json'))
    local = local_paths(sdk_dir: sdk_dir, manifest_path: manifest_path, local_dir: local_dir)
    upstream_names = upstream.to_h { [File.basename(_1).downcase, _1] }
    local.each do |path|
      recorded = upstream_names[File.basename(path).downcase] or next
      raise "#{relative(recorded, sdk_dir)} now records #{File.basename(path)}: " \
            "delete #{relative(path)} and its event_fixtures.yml entry"
    end
    (upstream + local).sort_by { File.basename(_1) }
  end

  # The downstream payload paths, each checked against its manifest entry and upstream unit test.
  def local_paths(sdk_dir: SDK_DIR, manifest_path: MANIFEST_PATH, local_dir: LOCAL_DIR)
    entries = YAML.safe_load_file(manifest_path) || {}
    files = Dir.glob(File.join(local_dir, '*.json')).to_h { [File.basename(_1, '.json').delete_suffix('Payload'), _1] }

    unlisted = files.keys - entries.keys
    raise "#{relative(local_dir)} has payloads without an event_fixtures.yml entry: #{unlisted.sort.join(', ')}" unless unlisted.empty?

    entries.sort.map do |name, attributes|
      path = files[name] or raise "event_fixtures.yml lists #{name}, but #{relative(local_dir)}/#{name}Payload.json is missing"
      java_test = attributes&.fetch('java_test', nil) or raise "event_fixtures.yml: #{name} has no java_test"
      verify_copy(path, File.join(sdk_dir, java_test))
      path
    end
  end

  def verify_copy(path, java_test_path)
    raise "#{relative(path)}: upstream unit test #{java_test_path} does not exist" unless File.exist?(java_test_path)

    payloads = java_json_payloads(File.read(java_test_path))
    return if payloads.include?(JSON.parse(File.read(path)))

    raise "#{relative(path)} differs from every `String json` payload in #{relative(java_test_path)}; " \
          'copy the payload again'
  end

  # The parsed JSON of each `String json = ...;` declaration in a Java source.
  def java_json_payloads(source)
    source.scan(JAVA_JSON_DECLARATION).filter_map do |(expression)|
      JSON.parse(expression.scan(JAVA_STRING).map { |(literal)| JSON.parse("\"#{literal}\"") }.join)
    rescue JSON::ParserError
      nil
    end
  end

  def relative(path, base = ROOT_DIR)
    path.delete_prefix("#{base}/")
  end
end
