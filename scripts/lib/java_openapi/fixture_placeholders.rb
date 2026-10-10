# frozen_string_literal: true

require 'json'

# Preprocesses upstream java-slack-sdk fixtures before the decode check, without changing any library type.
#
# The fixtures are recorded responses merged with objects that upstream java-slack-sdk's recorder fills with
# Java-typed placeholders (ObjectInitializer.initProperties in slack-api-client/src/test/java/util):
# String "", Integer/Long 123, Double 12.3, Boolean false. Two kinds of them break strict decoding:
#
#   * Placeholders at fields that scripts/java_type_overrides.yml retypes (`File#original_w: ""` where the
#     override says integer). They are removed: a property marked `x-java-type` whose value is the recorder's
#     placeholder for that Java type and contradicts the override.
#   * Placeholders inside Block Kit subtrees, which downstream swift-slack's hand-written SlackBlockKit
#     decodes (empty component schemas in the document). There, `""` URLs become https://example.com, an empty
#     text object `type` becomes plain_text, an empty rich text list `style` becomes bullet, and an empty
#     optional button or confirm `style` is dropped.
module FixturePlaceholders
  PLACEHOLDERS = { 'string' => '', 'integer' => 123, 'number' => 12.3, 'boolean' => false }.freeze
  BLOCK_KIT_URL_KEYS = %w[url image_url title_url provider_icon_url video_url thumbnail_url].freeze
  BLOCK_KIT_URL = 'https://example.com'
  BLOCK_KIT_TEXT_TYPE = 'plain_text'
  BLOCK_KIT_LIST_STYLE = 'bullet' # a rich text list's style is required, unlike button and confirm styles

  # Fixtures contain duplicate keys (the last one wins) and may nest deeply.
  LENIENT_JSON = { max_nesting: false, allow_duplicate_key: true }.freeze

  # Counts of what `Preprocessor#call` changed.
  Counts = Struct.new(:removed, :block_kit) do
    def initialize = super(0, 0)
  end

  module_function

  def parse(text)
    JSON.parse(text, **LENIENT_JSON)
  end

  # Does `value` have the JSON type `type` (an OpenAPI type name, or nil for untyped)?
  def matches_type?(value, type)
    case type
    when 'string' then value.is_a?(String)
    when 'integer' then value.is_a?(Integer) || (value.is_a?(Float) && value == value.to_i)
    when 'number' then value.is_a?(Numeric)
    when 'boolean' then [true, false].include?(value)
    when 'object' then value.is_a?(Hash)
    when 'array' then value.is_a?(Array)
    else true
    end
  end

  # Is `value` what the recorder writes for a field whose Java type maps to `java_type`?
  def placeholder?(java_type, value)
    return false unless PLACEHOLDERS.key?(java_type)

    placeholder = PLACEHOLDERS.fetch(java_type)
    case java_type
    when 'integer' then value.is_a?(Integer) && value == placeholder
    when 'number' then value.is_a?(Float) && value == placeholder
    else value == placeholder
    end
  end

  # A recorder placeholder at an overridden property that contradicts the override type.
  def placeholder_at_override?(schema, value)
    java_type = schema['x-java-type'] or return false
    placeholder?(java_type, value) && !matches_type?(value, schema['type'])
  end

  # An empty component schema stands for a SlackBlockKit type mapped through typeOverrides.
  def block_kit_schema?(schemas, name)
    schemas.fetch(name).empty?
  end

  # Walks a payload alongside its schema in the OpenAPI document and returns the preprocessed copy.
  class Preprocessor
    attr_reader :counts

    def initialize(document)
      @schemas = document.dig('components', 'schemas')
      @counts = Counts.new
    end

    def call(value, schema)
      if (name = schema['$ref']&.delete_prefix('#/components/schemas/'))
        return fix_block_kit(value) if FixturePlaceholders.block_kit_schema?(@schemas, name)

        schema = @schemas.fetch(name)
      end
      return call(value, alternative_for(value, schema['oneOf'])) if schema['oneOf']

      case value
      when Hash then preprocess_object(value, schema)
      when Array then schema['items'] ? value.map { |element| call(element, schema['items']) } : value
      else value
      end
    end

    private

    def preprocess_object(value, schema)
      properties = schema.fetch('properties', {})
      additional = schema['additionalProperties']
      value.each_with_object({}) do |(key, child), kept|
        property = properties[key] || (additional if additional.is_a?(Hash))
        if property && FixturePlaceholders.placeholder_at_override?(property, child)
          @counts.removed += 1
        else
          kept[key] = property ? call(child, property) : child
        end
      end
    end

    # The first `oneOf` alternative whose JSON type fits `value`, or an untyped schema.
    def alternative_for(value, alternatives)
      alternatives.find do |alternative|
        resolved = alternative['$ref'] ? @schemas.fetch(alternative['$ref'].delete_prefix('#/components/schemas/')) : alternative
        FixturePlaceholders.matches_type?(value, resolved['type'] || 'object')
      end || {}
    end

    # Replaces the recorder's placeholders inside a SlackBlockKit subtree.
    def fix_block_kit(value)
      case value
      when Array then value.map { |element| fix_block_kit(element) }
      when Hash then fix_block_kit_object(value)
      else value
      end
    end

    def fix_block_kit_object(object)
      text_object = object.key?('text') && object.key?('type')
      object.each_with_object({}) do |(key, child), fixed|
        if key == 'style' && child == '' && object['type'] == 'rich_text_list'
          fixed[key] = replaced(BLOCK_KIT_LIST_STYLE)
        elsif key == 'style' && child == ''
          @counts.block_kit += 1 # an optional style: drop it
        elsif BLOCK_KIT_URL_KEYS.include?(key) && child == ''
          fixed[key] = replaced(BLOCK_KIT_URL)
        elsif text_object && key == 'type' && child == ''
          fixed[key] = replaced(BLOCK_KIT_TEXT_TYPE)
        else
          fixed[key] = fix_block_kit(child)
        end
      end
    end

    def replaced(value)
      @counts.block_kit += 1
      value
    end
  end
end
