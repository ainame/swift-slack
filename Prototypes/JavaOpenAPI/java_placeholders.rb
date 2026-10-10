# frozen_string_literal: true

# java-slack-sdk's fixture recorder fills every field with a Java-typed placeholder before serializing it
# (ObjectInitializer.initProperties in slack-api-client/src/test/java/util/ObjectInitializer.java):
# String "", Integer/Long 123, Double 12.3, Boolean false. Slack never sends these at fields that
# type_overrides.yml retypes, but the recorded fixtures still carry them there (e.g. File#original_w: ""),
# and strict decoding into the override type (Int) rejects them. `strip` removes exactly those values.
# Keyed by the `x-java-type` marker gen_openapi.rb writes on an overridden property (the OpenAPI type of the Java field).
require "json"

module JavaPlaceholders
  PLACEHOLDERS = { "string" => "", "integer" => 123, "number" => 12.3, "boolean" => false }.freeze
  # Hand-written SlackBlockKit schemas: not described by the document, never descended into.
  HAND_WRITTEN = %w[Block View TextObject RichTextBlock].freeze

  module_function

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

  # Is `value` what initProperties writes for a field whose Java type maps to `java_type`?
  def placeholder?(java_type, value)
    return false unless PLACEHOLDERS.key?(java_type)

    placeholder = PLACEHOLDERS.fetch(java_type)
    case java_type
    when "integer" then value.is_a?(Integer) && value == placeholder
    when "number" then value.is_a?(Float) && value == placeholder
    else value == placeholder
    end
  end

  # An overridden property (one with `x-java-type`) whose value is the Java placeholder and contradicts the
  # override type.
  def placeholder_at_override?(schema, value)
    java_type = schema["x-java-type"] or return false
    placeholder?(java_type, value) && !matches_type?(value, schema["type"])
  end

  # Returns a copy of `value` (a response payload for `schema`) without the placeholder values at overridden
  # properties, and the number of values removed. `schemas` is components.schemas of the OpenAPI document.
  def strip(value, schema, schemas)
    removed = 0
    walk = lambda do |val, sch|
      if (ref = sch["$ref"])
        name = File.basename(ref)
        next val if HAND_WRITTEN.include?(name)

        sch = schemas.fetch(name)
      end
      case val
      when Hash
        properties = sch.fetch("properties", {})
        additional = sch["additionalProperties"]
        val.each_with_object({}) do |(key, child), kept|
          prop = properties[key] || (additional if additional.is_a?(Hash))
          if prop && placeholder_at_override?(prop, child)
            removed += 1
          else
            kept[key] = prop ? walk.(child, prop) : child
          end
        end
      when Array
        sch["items"] ? val.map { walk.(_1, sch["items"]) } : val
      else
        val
      end
    end
    [walk.(value, schema), removed]
  end

  # `strip` for the response payload of `method` ("team.info") in an openapi.json `document`.
  def strip_for_method(json, method, document)
    path_item = document["paths"]["/#{method}"] or return [json, 0]
    schema = path_item["post"]["responses"]["200"]["content"]["application/json"]["schema"]
    strip(json, schema, document["components"]["schemas"])
  end

  # Samples contain duplicate keys (the last one wins) and may nest deeply.
  LENIENT = { max_nesting: false, allow_duplicate_key: true }.freeze

  # Writes the fixture `source` of `method` to `dest` without the placeholders; returns how many were removed.
  def write_stripped_fixture(source, dest, method, document)
    json = JSON.parse(File.read(source, encoding: "UTF-8"), **LENIENT)
    stripped, removed = strip_for_method(json, method, document)
    File.write(dest, JSON.generate(stripped))
    removed
  end
end
