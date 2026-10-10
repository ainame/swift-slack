#!/usr/bin/env ruby
# frozen_string_literal: true

# Static check, no Swift involved: validates JSON samples against the schemas in all/openapi.json
# and lists every place where a JSON value's type differs from the schema.
# Hand-written SlackBlockKit schemas (Block, View, ...) are not descended into.
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

# Records [method, path, schema type, actual type] => count in `mismatches`.
def check(value, schema, path, method, mismatches)
  if schema.key?("$ref")
    name = schema["$ref"].split("/").last
    return if OVERRIDDEN.include?(name)

    schema = SCHEMAS.fetch(name)
  end
  return if value.nil? || schema.empty?

  type = schema["type"]
  unless matches_type?(value, type)
    key = [method, path, type, type_name(value)]
    mismatches[key] = mismatches.fetch(key, 0) + 1
    return
  end

  if type == "object" && value.is_a?(Hash)
    properties = schema.fetch("properties", {})
    additional = schema["additionalProperties"]
    value.each do |k, v|
      if properties.key?(k)
        check(v, properties[k], "#{path}.#{k}", method, mismatches)
      elsif additional.is_a?(Hash)
        check(v, additional, "#{path}.*", method, mismatches)
      end
    end
  elsif type == "array"
    value.each { |v| check(v, schema["items"], "#{path}[]", method, mismatches) }
  end
end

# Python repr() of a string, for the tuple-style output.
def py_repr(string)
  quote = string.include?("'") && !string.include?('"') ? '"' : "'"
  escaped = string.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
  escaped = escaped.gsub("'", "\\\\'") if quote == "'"
  "#{quote}#{escaped}#{quote}"
end

def run(label, payloads)
  mismatches = {}
  count = 0
  payloads.each do |method, json|
    path_item = DOCUMENT["paths"]["/#{method}"] or next
    schema = path_item["post"]["responses"]["200"]["content"]["application/json"]["schema"]
    count += 1
    check(json, schema, "", method, mismatches)
  end
  puts "== #{label}: #{count} payloads, #{mismatches.size} distinct mismatches"
  mismatches.sort.first(MAX_LINES).each do |key, n|
    puts "(#{key.map { |k| py_repr(k) }.join(", ")}) #{n}"
  end
end

fixtures = Dir.glob(File.join(VENDOR, "java-slack-sdk/json-logs/samples/api/*.json")).filter_map do |file|
  [File.basename(file, ".json"), JSON.parse(File.read(file, encoding: "UTF-8"), **LENIENT)]
rescue StandardError
  nil
end
run("java fixtures", fixtures)

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
run("api-ref examples", examples)
