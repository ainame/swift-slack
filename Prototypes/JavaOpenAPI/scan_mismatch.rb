#!/usr/bin/env ruby
# frozen_string_literal: true

# Static check, no Swift involved: validates JSON samples against the schemas in all/openapi.json
# and lists every place where a JSON value's type differs from the schema.
# Hand-written SlackBlockKit schemas (Block, View, ...) are not descended into.
#
# Policy (see type_overrides.yml): a java-fixtures mismatch must be covered by a type override, otherwise this
# script prints it and exits non-zero. Mismatches seen only in the api-ref docs examples are information only.
# An overridden property carries `x-java-type` (the type the Java source declares): a value that contradicts
# it is "explained" by the override. The fixture generator's own placeholder at an overridden property
# ("" / 123 / 12.3 / false, see java_placeholders.rb) is counted separately, not as a mismatch.
#
# Output is one line per distinct mismatch:
#   <method>  <path in the response>  expected <schema type>, got <JSON type> (×<occurrences>)
#
# Usage: scan_mismatch.rb

require "json"
require_relative "java_placeholders"

HERE = __dir__
VENDOR = File.expand_path("../../vendor", HERE)
DOCUMENT = JSON.parse(File.read(File.join(HERE, "all/openapi.json"), encoding: "UTF-8"))
SCHEMAS = DOCUMENT.dig("components", "schemas")
DOCS_LINE_LIMIT = 60

# A value whose JSON type differs from the one the schema asks for.
Mismatch = Struct.new(:method, :path, :expected, :actual)

# What a scan found: `mismatches` and `explained` count occurrences per Mismatch (`explained`: the value
# contradicts the Java type but matches its type override); `placeholders` holds the [method, path] pairs
# where a Java-typed placeholder sits at an overridden property.
Findings = Struct.new(:payloads, :mismatches, :explained, :placeholders) do
  def initialize(payloads = 0) = super(payloads, Hash.new(0), Hash.new(0), Set.new)
end

# The JSON (OpenAPI) type name of a parsed value.
def json_type(value)
  case value
  when String then "string"
  when Integer then "integer"
  when Float then "number"
  when true, false then "boolean"
  when Hash then "object"
  when Array then "array"
  end
end

def check(value, schema, path, method, findings)
  if (ref = schema["$ref"])
    name = File.basename(ref)
    return if JavaPlaceholders::HAND_WRITTEN.include?(name)

    schema = SCHEMAS.fetch(name)
  end
  return if value.nil?

  java_type = schema["x-java-type"]
  if java_type && !JavaPlaceholders.matches_type?(value, java_type)
    findings.explained[Mismatch.new(method, path, java_type, json_type(value))] += 1
  end

  type = schema["type"]
  unless JavaPlaceholders.matches_type?(value, type)
    if JavaPlaceholders.placeholder_at_override?(schema, value)
      findings.placeholders << [method, path]
    else
      findings.mismatches[Mismatch.new(method, path, type, json_type(value))] += 1
    end
    return
  end

  case [type, value]
  in ["object", Hash]
    properties = schema.fetch("properties", {})
    additional = schema["additionalProperties"]
    value.each do |key, child|
      if properties.key?(key)
        check(child, properties[key], "#{path}.#{key}", method, findings)
      elsif additional.is_a?(Hash)
        check(child, additional, "#{path}.*", method, findings)
      end
    end
  in ["array", Array]
    value.each { |child| check(child, schema["items"], "#{path}[]", method, findings) }
  else
    nil # scalars and untyped values have nothing to descend into
  end
end

def response_schema(method)
  DOCUMENT.dig("paths", "/#{method}", "post", "responses", "200", "content", "application/json", "schema")
end

# Checks each [method, json] payload against the response schema of its method (methods without one are skipped).
def scan(payloads)
  payloads.each_with_object(Findings.new) do |(method, json), findings|
    next unless (schema = response_schema(method))

    findings.payloads += 1
    check(json, schema, "", method, findings)
  end
end

# Prints the mismatches as an aligned table, at most `limit` rows.
def report(title, findings, limit: nil)
  mismatches = findings.mismatches.sort_by { |mismatch, _| mismatch.to_a }
  puts "== #{title}: #{findings.payloads} payloads, #{mismatches.size} distinct mismatches"
  rows = mismatches.map do |m, count|
    [m.method, m.path, "expected #{m.expected}, got #{m.actual}", "(×#{count})"]
  end
  widths = rows.transpose.map { |column| column.map(&:length).max }
  rows.first(limit || rows.size).each do |row|
    puts "  #{row.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ").rstrip}"
  end
  puts "  ... #{rows.size - limit} more" if limit && rows.size > limit
end

def parse_json(text) = JSON.parse(text, **JavaPlaceholders::LENIENT)

fixtures = Dir.glob(File.join(VENDOR, "java-slack-sdk/json-logs/samples/api/*.json")).filter_map do |file|
  [File.basename(file, ".json"), parse_json(File.read(file, encoding: "UTF-8"))]
rescue JSON::ParserError
  nil
end
fixture_findings = scan(fixtures)
report("java fixtures (unexplained mismatches)", fixture_findings)

# Only successful (`ok: true`) examples count; a malformed file is skipped.
examples = Dir.glob(File.join(VENDOR, "slack-api-ref/methods/*/*.json")).flat_map do |file|
  method = File.basename(file, ".json")
  parse_json(File.read(file, encoding: "UTF-8")).dig("response", "examples").filter_map do |example|
    json = parse_json(example)
    [method, json] if json.is_a?(Hash) && json["ok"] == true
  end
rescue JSON::ParserError, NoMethodError, TypeError
  []
end
docs_findings = scan(examples)
report("api-ref examples (information only)", docs_findings, limit: DOCS_LINE_LIMIT)

unexplained = fixture_findings.mismatches.size
puts "== summary: #{fixture_findings.explained.size} fixture mismatches explained by type_overrides.yml " \
     "(plus #{fixture_findings.placeholders.size} Java-typed placeholder values at overridden fields), " \
     "#{unexplained} unexplained, #{docs_findings.mismatches.size} docs-example mismatches (information only)"
exit 1 if unexplained.positive?
