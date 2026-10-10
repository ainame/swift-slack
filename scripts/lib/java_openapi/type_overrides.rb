# frozen_string_literal: true

require 'set'
require 'yaml'

# Explicit per-field exceptions to "types come from the Java declarations" (scripts/java_type_overrides.yml).
#
# Each entry is keyed `<Java FQN of the declaring class>#<JSON key>` and replaces the Java-derived schema of
# that one field with a JSON type, an untyped value, or a schema (`schema`, which may refer to
# scripts/handwritten_schemas.yml). The emitted schema keeps the Java type in `x-java-type` for the fixture
# checks and gets a `description` that Apple's swift-openapi-generator renders as a `///` comment.
#
# An entry with `added: true` instead adds a property that recorded responses contain but the Java class does
# not declare.
class TypeOverrides
  JSON_TYPES = %w[integer number string boolean].freeze
  NOUNS = {
    'integer' => 'integers', 'number' => 'numbers', 'string' => 'strings', 'boolean' => 'booleans',
    'untyped' => 'values of another type', 'schema' => 'values of another shape'
  }.freeze

  Entry = Struct.new(:key, :type, :schema, :java_type, :added, :reason, :evidence, keyword_init: true) do
    def fqn = key.split('#', 2).first
    def json_key = key.split('#', 2).last
  end

  def self.load(path)
    new(YAML.safe_load_file(path) || {}, source: File.basename(path))
  end

  def initialize(entries, source: 'type overrides')
    @source = source
    @entries = entries.to_h do |key, attributes|
      [key, Entry.new(key: key, type: attributes['type'], schema: attributes['schema'],
                      java_type: attributes['java_type'].to_s.delete(' '), added: attributes['added'] == true,
                      reason: attributes['reason'],
                      evidence: Array(attributes['evidence']))]
    end
    @entries.each_value { |entry| validate_entry_shape(entry) }
    @applied = Set.new
  end

  def entries
    @entries.values
  end

  # Fails when an entry names a class or field that no longer exists, or a field whose declared type changed.
  def validate!(index)
    @entries.each_value do |entry|
      java_class = index.fully_qualified(entry.fqn) or fail_entry(entry, "class #{entry.fqn} no longer exists")
      field = java_class.fields.find { |candidate| candidate.json_key == entry.json_key }
      if entry.added
        fail_entry(entry, "#{java_class.name} now declares `#{entry.json_key}`; remove `added`") if field
        next
      end
      fail_entry(entry, "#{java_class.name} has no field with JSON key `#{entry.json_key}`") unless field
      next if field.type.to_s == entry.java_type

      fail_entry(entry, "java_type is `#{entry.java_type}` but the source declares `#{field.type}`")
    end
  end

  # Properties to add to the schema of `java_class`, by JSON key.
  def additions_for(java_class)
    entries.select { |entry| entry.added && entry.fqn == java_class.fqn }.to_h do |entry|
      @applied << entry.key
      description = "Not declared by java-slack-sdk `#{java_class.nested_name}`, but recorded responses include it."
      [entry.json_key, entry.schema.merge('description' => description)]
    end
  end

  # The schema for `field` declared in `owner` (JSON key `key`): the override, or `schema` unchanged.
  def apply(schema, owner, field, key)
    entry = @entries["#{owner.fqn}##{key}"] or return schema
    @applied << entry.key

    description = "Type differs from java-slack-sdk: `#{owner.nested_name}.#{field.name}` is declared " \
                  "`#{entry.java_type}`, but recorded responses send #{NOUNS.fetch(entry.type)}."
    replacement =
      case entry.type
      when 'untyped' then {}
      when 'schema' then entry.schema
      else { 'type' => entry.type }
      end
    replacement.merge('description' => description, 'x-java-type' => schema['type'] || 'untyped')
  end

  # Keys of entries that no generated schema used, e.g. ones for classes of unsupported methods.
  def unused_keys
    @entries.keys - @applied.to_a
  end

  private

  def validate_entry_shape(entry)
    unless (JSON_TYPES + %w[untyped schema]).include?(entry.type)
      fail_entry(entry, "type must be one of #{(JSON_TYPES + %w[untyped schema]).join(', ')}")
    end
    fail_entry(entry, 'a schema entry needs `schema`') if entry.type == 'schema' && !entry.schema.is_a?(Hash)
    fail_entry(entry, 'an added field needs `type: schema`') if entry.added && entry.type != 'schema'
    fail_entry(entry, 'an added field has no java_type') if entry.added && !entry.java_type.empty?
    fail_entry(entry, 'reason is missing') if entry.reason.to_s.empty?
    fail_entry(entry, 'evidence is missing') if entry.evidence.empty?
  end

  def fail_entry(entry, message)
    raise "#{@source}: #{entry.key}: #{message}"
  end
end
