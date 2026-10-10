#!/usr/bin/env ruby
# frozen_string_literal: true

# Decodes the upstream java-slack-sdk fixture of every generated Web API method and event with the real
# generated types, and fails unless all of them decode.
#
#   1. Preprocesses the fixtures (scripts/lib/java_openapi/fixture_placeholders.rb) into .tmp/Fixtures/
#      api/<method>.json and events/<EventSchema>.json, using .tmp/WebAPI/openapi.json from `make generate`.
#   2. Runs the Swift tests that read them: FixtureDecodingTests in SlackClientTests (responses) and
#      SlackAppTests (events). Without SLACK_FIXTURES_DIR those tests are skipped.
#
# Usage: check_fixtures.rb [--prepare-only]

require 'fileutils'
require 'json'
require_relative 'lib/java_openapi/fixture_placeholders'

Encoding.default_external = Encoding::UTF_8

ROOT_DIR = File.expand_path('..', __dir__)
OPENAPI_PATH = File.join(ROOT_DIR, '.tmp/WebAPI/openapi.json')
SAMPLES_DIR = File.join(ROOT_DIR, 'vendor/java-slack-sdk/json-logs/samples')
OUTPUT_DIR = File.join(ROOT_DIR, '.tmp/Fixtures')

def ref(name)
  { '$ref' => "#/components/schemas/#{name}" }
end

# Event fixtures are either the event itself or an Events API envelope around it.
def event_payload(json)
  json.key?('token') && json.key?('event') ? json['event'] : json
end

# The fixture file of an event schema: IMCloseEvent => ImClosePayload.json (names differ only in case).
def event_fixture_path(schema_name)
  wanted = "#{schema_name.delete_suffix('Event')}Payload.json".downcase
  Dir.glob(File.join(SAMPLES_DIR, 'events/*.json')).find { |path| File.basename(path).downcase == wanted } or
    raise "no upstream fixture for #{schema_name}"
end

def write_fixture(directory, name, json, schema, preprocessor)
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "#{name}.json"), JSON.generate(preprocessor.call(json, schema)))
end

def prepare
  abort "#{OPENAPI_PATH} is missing: run `make generate` first" unless File.exist?(OPENAPI_PATH)

  document = JSON.parse(File.read(OPENAPI_PATH))
  preprocessor = FixturePlaceholders::Preprocessor.new(document)
  FileUtils.rm_rf(OUTPUT_DIR)

  document['paths'].each do |path, item|
    method = path.delete_prefix('/')
    schema = item.dig('post', 'responses', '200', 'content', 'application/json', 'schema')
    json = FixturePlaceholders.parse(File.read(File.join(SAMPLES_DIR, "api/#{method}.json")))
    write_fixture(File.join(OUTPUT_DIR, 'api'), method, json, schema, preprocessor)
  end
  document.fetch('x-slack-events').each_key do |name|
    json = event_payload(FixturePlaceholders.parse(File.read(event_fixture_path(name))))
    write_fixture(File.join(OUTPUT_DIR, 'events'), name, json, ref(name), preprocessor)
  end

  counts = preprocessor.counts
  puts "Prepared #{document['paths'].size} response and #{document['x-slack-events'].size} event fixtures " \
       "(#{counts.removed} placeholders removed, #{counts.block_kit} Block Kit placeholders replaced)"
end

prepare
unless ARGV.include?('--prepare-only')
  system({ 'SLACK_FIXTURES_DIR' => OUTPUT_DIR }, 'swift', 'test', '--filter', 'FixtureDecodingTests', chdir: ROOT_DIR) or
    abort 'Fixture decoding failed'
end
