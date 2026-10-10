#!/usr/bin/env ruby
# frozen_string_literal: true

# Static check, no Swift involved: validates JSON samples against the schemas in all/openapi.json
# and lists every place where a JSON value's type differs from the schema.
# Hand-written SlackBlockKit schemas (Block, View, ...) are not descended into.
#
# Policy (see type_overrides.yml): a java-fixtures mismatch must be covered by a type override, otherwise this
# script prints it and exits non-zero. Mismatches seen only in the api-ref docs examples are information only.
# An overridden property carries `x-java-type` (the type the Java source declares): a value that contradicts
# it is "explained" by the override. A value of the Java type at an overridden property is the fixture
# generator's own placeholder ("" / 123 / false) and is counted separately, not as a mismatch.
#
# Usage: scan_mismatch.rb

require "json"

HERE = File.expand_path(__dir__)
VENDOR = File.expand_path("../../vendor", HERE)
DOCUMENT = JSON.parse(File.read(File.join(HERE, "all/openapi.json"), encoding: "UTF-8"))
SCHEMAS = DOCUMENT["components"]["schemas"]
OVERRIDDEN = %w[Block View TextObject RichTextBlock].freeze
MAX_LINES = 60
# Samples contain duplicate keys (last wins, as in Python) and may nest deeply.
LENIENT = { max_nesting: false, allow_duplicate_key: true }.freeze

# Python-style type names, so output stays comparable with earlier reports.
def type_name(value)
  case value
  when String then "str"
  when Integer then "int"
  when Float then "float"
  when true, false then "bool"
  when Hash then "dict"
  when Array then "list"
  end
end

def matches_type?(value, type)
  case type
  when "string" then value.is_a?(String)
  when "integer" then value.is_a?(Integer) || (value.is_a?(Float) && value == value.to_i)
  when "number" then value.is_a?(Numeric)
  when "boolean" then value == true || value == false
  when "object" then value.is_a?(Hash)
  when "array" then value.is_a?(Array)
  else true
  end
end

# What a scan found, each keyed by [method, path, ...]: `mismatches` (value type differs from the schema),
# `explained` (value contradicts the Java type but matches its type override), `placeholders` (Java-typed value
# at an overridden property).
Tally = Struct.new(:mismatches, :explained, :placeholders)

# Records [method, path, schema type, actual type] => count in the tally.
def check(value, schema, path, method, tally)
  if schema.key?("$ref")
    name = schema["$ref"].split("/").last
    return if OVERRIDDEN.include?(name)

    schema = SCHEMAS.fetch(name)
  end
  return if value.nil?

  java_type = schema["x-java-type"]
  if java_type && !matches_type?(value, java_type)
    key = [method, path, java_type, type_name(value)]
    tally.explained[key] = tally.explained.fetch(key, 0) + 1
  end

  type = schema["type"]
  unless matches_type?(value, type)
    if java_type && matches_type?(value, java_type)
      tally.placeholders[[method, path]] = true
      return
    end
    key = [method, path, type, type_name(value)]
    tally.mismatches[key] = tally.mismatches.fetch(key, 0) + 1
    return
  end

  if type == "object" && value.is_a?(Hash)
    properties = schema.fetch("properties", {})
    additional = schema["additionalProperties"]
    value.each do |k, v|
      if properties.key?(k)
        check(v, properties[k], "#{path}.#{k}", method, tally)
      elsif additional.is_a?(Hash)
        check(v, additional, "#{path}.*", method, tally)
      end
    end
  elsif type == "array"
    value.each { |v| check(v, schema["items"], "#{path}[]", method, tally) }
  end
end

# Python repr() of a string, for the tuple-style output.
def py_repr(string)
  quote = string.include?("'") && !string.include?('"') ? '"' : "'"
  escaped = string.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
  escaped = escaped.gsub("'", "\\\\'") if quote == "'"
  "#{quote}#{escaped}#{quote}"
end

# Prints the mismatches (all of them when `limit` is nil) and returns the sizes of the tally.
def run(label, payloads, limit: MAX_LINES)
  tally = Tally.new({}, {}, {})
  count = 0
  payloads.each do |method, json|
    path_item = DOCUMENT["paths"]["/#{method}"] or next
    schema = path_item["post"]["responses"]["200"]["content"]["application/json"]["schema"]
    count += 1
    check(json, schema, "", method, tally)
  end
  puts "== #{label}: #{count} payloads, #{tally.mismatches.size} distinct mismatches"
  tally.mismatches.sort.first(limit || tally.mismatches.size).each do |key, n|
    puts "(#{key.map { |k| py_repr(k) }.join(", ")}) #{n}"
  end
  tally.to_a.map(&:size)
end

fixtures = Dir.glob(File.join(VENDOR, "java-slack-sdk/json-logs/samples/api/*.json")).filter_map do |file|
  [File.basename(file, ".json"), JSON.parse(File.read(file, encoding: "UTF-8"), **LENIENT)]
rescue StandardError
  nil
end
unexplained, explained, placeholders = run("java fixtures (unexplained mismatches)", fixtures, limit: nil)

# Only successful examples of each api-ref method file count; a malformed file stops that file's scan.
examples = []
Dir.glob(File.join(VENDOR, "slack-api-ref/methods/*/*.json")).each do |file|
  method = File.basename(file, ".json")
  begin
    JSON.parse(File.read(file, encoding: "UTF-8"), **LENIENT)["response"]["examples"].each do |e|
      json = JSON.parse(e, **LENIENT)
      raise TypeError, "not an object" unless json.is_a?(Hash)

      examples << [method, json] if json["ok"] == true
    end
  rescue StandardError
    next
  end
end
docs_info, = run("api-ref examples (information only)", examples)

puts "== summary: #{explained} fixture mismatches explained by type_overrides.yml " \
     "(plus #{placeholders} Java-typed placeholder values at overridden fields), #{unexplained} unexplained, #{docs_info} docs-example mismatches (information only)"
exit 1 if unexplained.positive?
