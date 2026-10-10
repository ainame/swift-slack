#!/usr/bin/env ruby
# frozen_string_literal: true

# Static check, no Swift involved: compares every upstream java-slack-sdk fixture of a generated method or
# event with its schema in .tmp/WebAPI/openapi.json and lists each value whose JSON type differs.
#
# Policy (scripts/java_type_overrides.yml): a fixture mismatch must be explained by a type override,
# otherwise this script prints it and exits non-zero. An overridden property keeps the Java type in
# `x-java-type`; a value that contradicts the Java type but matches the override counts as explained, and
# the recorder's own placeholder at an overridden property is counted separately. Mismatches in upstream
# slack-api-ref docs examples are printed for information only. SlackBlockKit subtrees are not descended into.
#
# A key that the schema does not declare is a mismatch too ("expected undeclared"): the recorder only fills
# Java fields, so such a key comes from a recorded response. Declare it with an `added` type override.
#
# Usage: scan_fixture_mismatches.rb

require 'json'
require 'set'
require_relative 'lib/java_openapi/fixture_placeholders'

Encoding.default_external = Encoding::UTF_8

ROOT_DIR = File.expand_path('..', __dir__)
OPENAPI_PATH = File.join(ROOT_DIR, '.tmp/WebAPI/openapi.json')
SAMPLES_DIR = File.join(ROOT_DIR, 'vendor/java-slack-sdk/json-logs/samples')
DOCS_LINE_LIMIT = 60

# A value whose JSON type differs from the one the schema asks for.
Mismatch = Struct.new(:source, :path, :expected, :actual)

# What a scan found, counted per distinct Mismatch.
class Findings
  attr_accessor :payloads
  attr_reader :mismatches, :explained, :placeholders

  def initialize
    @payloads = 0
    @mismatches = Hash.new(0)
    @explained = Hash.new(0)
    @placeholders = Set.new
  end
end

class Scanner
  def initialize(document)
    @schemas = document.dig('components', 'schemas')
  end

  # Checks [source name, JSON, schema] triples.
  def scan(payloads)
    payloads.each_with_object(Findings.new) do |(source, json, schema), findings|
      findings.payloads += 1
      check(json, schema, '', source, findings)
    end
  end

  private

  def json_type(value)
    case value
    when String then 'string'
    when Integer then 'integer'
    when Float then 'number'
    when true, false then 'boolean'
    when Hash then 'object'
    when Array then 'array'
    end
  end

  def resolve(schema)
    name = schema['$ref']&.delete_prefix('#/components/schemas/') or return schema
    @schemas.fetch(name)
  end

  def check(value, schema, path, source, findings)
    schema = resolve(schema)
    return if value.nil? || schema.empty? # untyped, or a SlackBlockKit type

    if (alternatives = schema['oneOf'])
      matching = alternatives.find { |alternative| fits?(value, alternative, source) }
      return record(findings.mismatches, source, path, 'oneOf', value) unless matching

      return check(value, matching, path, source, findings)
    end

    java_type = schema['x-java-type']
    if java_type && !FixturePlaceholders.matches_type?(value, java_type)
      record(findings.explained, source, path, java_type, value)
    end

    unless FixturePlaceholders.matches_type?(value, schema['type'])
      if FixturePlaceholders.placeholder_at_override?(schema, value)
        findings.placeholders << [source, path]
      else
        record(findings.mismatches, source, path, schema['type'], value)
      end
      return
    end

    descend(value, schema, path, source, findings)
  end

  # Does `value` match a `oneOf` alternative without any mismatch inside it?
  def fits?(value, alternative, source)
    return false unless FixturePlaceholders.matches_type?(value, resolve(alternative)['type'])

    trial = Findings.new
    check(value, alternative, '', source, trial)
    trial.mismatches.empty?
  end

  def descend(value, schema, path, source, findings)
    case value
    when Hash
      properties = schema.fetch('properties', {})
      additional = schema['additionalProperties']
      value.each do |key, child|
        if properties.key?(key)
          check(child, properties[key], "#{path}.#{key}", source, findings)
        elsif additional.is_a?(Hash)
          check(child, additional, "#{path}.*", source, findings)
        elsif !additional
          record(findings.mismatches, source, "#{path}.#{key}", 'undeclared', child)
        end
      end
    when Array
      value.each { |child| check(child, schema['items'], "#{path}[]", source, findings) } if schema['items']
    end
  end

  def record(counter, source, path, expected, value)
    counter[Mismatch.new(source, path, expected, json_type(value))] += 1
  end
end

# Prints the mismatches as an aligned table, at most `limit` rows.
def report(title, findings, limit: nil)
  mismatches = findings.mismatches.sort_by { |mismatch, _| mismatch.to_a }
  puts "== #{title}: #{findings.payloads} payloads, #{mismatches.size} distinct mismatches"
  rows = mismatches.map { |m, count| [m.source, m.path, "expected #{m.expected}, got #{m.actual}", "(x#{count})"] }
  return if rows.empty?

  widths = rows.transpose.map { |column| column.map(&:length).max }
  rows.first(limit || rows.size).each do |row|
    puts "  #{row.zip(widths).map { |cell, width| cell.ljust(width) }.join('  ').rstrip}"
  end
  puts "  ... #{rows.size - limit} more" if limit && rows.size > limit
end

def ref(name)
  { '$ref' => "#/components/schemas/#{name}" }
end

def read_json(path)
  FixturePlaceholders.parse(File.read(path))
end

abort "#{OPENAPI_PATH} is missing: run `make generate` first" unless File.exist?(OPENAPI_PATH)
document = JSON.parse(File.read(OPENAPI_PATH))
scanner = Scanner.new(document)
response_schemas = document['paths'].to_h do |path, item|
  [path.delete_prefix('/'), item.dig('post', 'responses', '200', 'content', 'application/json', 'schema')]
end

fixtures = response_schemas.map do |method, schema|
  [method, read_json(File.join(SAMPLES_DIR, "api/#{method}.json")), schema]
end
event_files = Dir.glob(File.join(SAMPLES_DIR, 'events/*.json')).to_h { |path| [File.basename(path).downcase, path] }
fixtures += document.fetch('x-slack-events').keys.map do |name|
  json = read_json(event_files.fetch("#{name.delete_suffix('Event')}Payload.json".downcase))
  json = json['event'] if json.key?('token') && json.key?('event')
  [name, json, ref(name)]
end
fixture_findings = scanner.scan(fixtures)
report('java-slack-sdk fixtures (unexplained mismatches)', fixture_findings)

# Only successful (`ok: true`) examples count; a malformed docs file is skipped.
examples = Dir.glob(File.join(ROOT_DIR, 'vendor/slack-api-ref/methods/*/*.json')).flat_map do |path|
  method = File.basename(path, '.json')
  schema = response_schemas[method] or next []
  read_json(path).dig('response', 'examples').filter_map do |example|
    json = FixturePlaceholders.parse(example)
    [method, json, schema] if json.is_a?(Hash) && json['ok'] == true
  end
rescue JSON::ParserError, NoMethodError, TypeError
  []
end
docs_findings = scanner.scan(examples)
report('slack-api-ref examples (information only)', docs_findings, limit: DOCS_LINE_LIMIT)

unexplained = fixture_findings.mismatches.size
puts "== summary: #{fixture_findings.explained.size} fixture mismatches explained by java_type_overrides.yml " \
     "(plus #{fixture_findings.placeholders.size} Java-typed placeholder values at overridden fields), " \
     "#{unexplained} unexplained, #{docs_findings.mismatches.size} docs-example mismatches (information only)"
exit 1 if unexplained.positive?
