# frozen_string_literal: true

require 'set'
require_relative 'class_index'
require_relative 'gson_adapters'

# Builds OpenAPI 3.1 component schemas from parsed upstream java-slack-sdk classes.
#
# Rules:
#   * Roots (Web API responses and events) are added under an explicit schema name.
#   * Other top-level classes become shared named schemas, referenced with `$ref`. Nested (inner) classes
#     are emitted inline at the use site, so Apple's swift-openapi-generator nests them in the parent as
#     `<Property>Payload` and same-named inner classes never collide.
#   * Every property is optional except the ones a root asks for (`ok` of a response, `type` of an event).
#     Java declarations carry no nullability, and Slack omits fields depending on the context.
#   * Property names follow Gson: @SerializedName, otherwise the snake_case field name. Superclass fields
#     come first.
#   * Types read through a Gson adapter follow GsonAdapters; Block Kit types map onto downstream swift-slack's
#     hand-written SlackBlockKit; enums become strings; TypeOverrides replaces individual fields.
#   * Anything that cannot be translated raises with the Java file and line.
class SchemaBuilder
  RESPONSE_PACKAGE = 'com.slack.api.methods.response'
  BLOCK_KIT_PACKAGES = %w[com.slack.api.model.block com.slack.api.model.view].freeze
  # Java Block Kit types folded onto a SlackBlockKit type of another name.
  BLOCK_KIT_ALIASES = {
    'PlainTextObject' => 'TextObject',
    'MarkdownTextObject' => 'TextObject',
    'LayoutBlock' => 'Block',
  }.freeze

  COLLECTIONS = Set['List', 'Set', 'Collection', 'ArrayList', 'Iterable', 'LinkedList']
  MAPS = Set['Map', 'HashMap', 'LinkedHashMap', 'TreeMap']
  SCALARS = {
    'string' => Set['String', 'CharSequence'],
    'integer' => Set['Integer', 'int', 'Long', 'long', 'Short', 'short', 'BigInteger', 'Byte', 'byte'],
    'number' => Set['Double', 'double', 'Float', 'float', 'Number', 'BigDecimal'],
    'boolean' => Set['Boolean', 'boolean'],
  }.freeze
  # Arbitrary JSON in Java (`Object`, Gson trees): emitted as `{}`.
  UNTYPED = Set['Object', 'JsonElement', 'JsonObject', 'JsonArray']
  # Types outside the parsed sources, by the name written in them.
  EXTERNAL_TYPES = { 'Instant' => 'java.time.Instant' }.freeze

  attr_reader :report

  # `handwritten_schemas`: name => schema from scripts/handwritten_schemas.yml.
  # `block_kit_types`: public type names of downstream swift-slack's SlackBlockKit module.
  def initialize(index, type_overrides:, handwritten_schemas:, block_kit_types:)
    @index = index
    @type_overrides = type_overrides
    @handwritten_schemas = handwritten_schemas
    @block_kit_types = block_kit_types.to_set
    @components = {}     # schema name => schema
    @names_by_fqn = {}   # fqn of a named class => schema name
    @type_mappings = {}  # placeholder schema name => Swift type, for typeOverrides
    @report = { enums: Set.new, untyped_adapters: Set.new, declared_adapters: Set.new }
  end

  # Adds `java_class` as the named schema `name`. `required` lists JSON keys that must be present.
  def add_root(name, java_class, required: [])
    claim_name(name, java_class)
    schema = object_schema(java_class, [])
    missing = required - schema['properties'].keys
    raise "#{java_class.fqn} has no #{missing.join(', ')} field to require" unless missing.empty?

    schema['required'] = required unless required.empty?
    @components[name] = schema
  end

  # Component schemas sorted by name, including empty placeholders for types of other Swift modules.
  def components
    @components.sort_by { |name, _| name }.to_h
  end

  # Placeholder schema name => Swift type, for swift-openapi-generator's typeOverrides.
  def type_mappings
    @type_mappings.sort.to_h
  end

  # Swift modules that typeOverrides point into.
  def mapped_modules
    @mapped_modules ||= Set.new
  end

  # Registers an empty placeholder schema that typeOverrides maps onto `swift_type` of `module_name`.
  def map_to_swift(schema_name, swift_type, module_name)
    if @type_mappings.key?(schema_name) && @type_mappings[schema_name] != swift_type
      raise "schema #{schema_name} is mapped to both #{@type_mappings[schema_name]} and #{swift_type}"
    end

    @type_mappings[schema_name] = swift_type
    mapped_modules << module_name
    @components[schema_name] ||= {}
    ref(schema_name)
  end

  # `$ref` to the shared schema of a top-level model class, emitting it on first use.
  def shared_ref(java_class)
    name = @names_by_fqn[java_class.fqn]
    unless name
      name = java_class.name
      claim_name(name, java_class)
      @components[name] = nil # reserve the name first so recursive types terminate
      @components[name] = object_schema(java_class, [])
    end
    ref(name)
  end

# `$ref` to the hand-written schema `name`, emitting it (and what it refers to) on first use.
def handwritten_ref(name)
  schema = @handwritten_schemas.fetch(name) { raise "scripts/handwritten_schemas.yml has no schema #{name}" }
  unless @components.key?(name)
    @components[name] = nil # reserve the name first so recursive references terminate
    @components[name] = expand_handwritten(schema, "handwritten schema #{name}")
  end
  ref(name)
end

# Hand-written schemas that nothing referenced.
def unused_handwritten_schemas
  @handwritten_schemas.keys - @components.keys
end

private

# Replaces `x-java-class` markers with the Java-derived schema and emits referenced hand-written schemas.
def expand_handwritten(fragment, where)
  case fragment
  when Array
    fragment.map { |element| expand_handwritten(element, where) }
  when Hash
    if (fqn = fragment['x-java-class'])
      java_class = @index.fully_qualified(fqn) or raise "#{where}: unknown x-java-class #{fqn}"
      return class_schema_for(java_class, "#{where} (#{fqn})", [])
    end
    if (name = fragment['$ref']&.delete_prefix('#/components/schemas/')) && @handwritten_schemas.key?(name)
      handwritten_ref(name)
    end
    fragment.transform_values { |value| expand_handwritten(value, where) }
  else
    fragment
  end
end

def ref(name)
    { '$ref' => "#/components/schemas/#{name}" }
  end

  # Reserves `name` for the class `java_class`, failing when another class already uses it.
  def claim_name(name, java_class)
    if (owner = @names_by_fqn.key(name)) && owner != java_class.fqn
      raise "schema name #{name} is used by both #{owner} and #{java_class.fqn}"
    end
    if (existing = @names_by_fqn[java_class.fqn]) && existing != name
      raise "#{java_class.fqn} is emitted as both #{existing} and #{name}"
    end

    @names_by_fqn[java_class.fqn] = name
  end

  # Object schema with every serialized field of `java_class` as an optional property.
  # `inline_stack` holds the inner classes being expanded, to detect recursion.
  def object_schema(java_class, inline_stack)
    properties = @index.fields_of(java_class).to_h do |key, (field, owner)|
      where = "#{owner.file.path}:#{field.type.line} (#{owner.fqn}.#{field.name})"
      schema = type_schema(field.type, owner, where, inline_stack)
      [key, expand_handwritten(@type_overrides.apply(schema, owner, field, key), where)]
    end
    @type_overrides.additions_for(java_class).each do |key, schema|
      properties[key] = expand_handwritten(schema, "#{java_class.fqn}##{key}")
    end
    { 'type' => 'object', 'properties' => properties }
  end

  # Schema for a type written inside class `context`.
  def type_schema(type, context, where, inline_stack)
    schema = element_schema(type, context, where, inline_stack)
    type.dims.times { schema = { 'type' => 'array', 'items' => schema } }
    schema
  end

  def element_schema(type, context, where, inline_stack)
    name = type.simple_name
    if COLLECTIONS.include?(name)
      raise "#{where}: raw collection type" if type.args.empty?

      { 'type' => 'array', 'items' => type_schema(type.args[0], context, where, inline_stack) }
    elsif MAPS.include?(name)
      raise "#{where}: raw map type" if type.args.size != 2

      value = type_schema(type.args[1], context, where, inline_stack)
      { 'type' => 'object', 'additionalProperties' => value.empty? ? true : value }
    elsif (json_type = SCALARS.find { |_, names| names.include?(name) }&.first)
      { 'type' => json_type }
    elsif UNTYPED.include?(name)
      {}
    else
      class_schema(type, context, where, inline_stack)
    end
  end

  # Schema for a type that must be one of the parsed classes (or a type read through a Gson adapter).
  def class_schema(type, context, where, inline_stack)
    java_class = @index.resolve(context, type.name)
    return class_schema_for(java_class, where, inline_stack) if java_class

    fqn = EXTERNAL_TYPES.fetch(type.name, type.name)
    decision = GsonAdapters.decision_for(fqn) or raise "#{where}: cannot resolve type `#{type.name}`"
    adapter_schema(fqn, decision, where)
  end

  def class_schema_for(java_class, where, inline_stack)
    fqn = java_class.fqn
    decision = GsonAdapters.decision_for(fqn)
    return adapter_schema(fqn, decision, where) if decision && decision.kind != :declared

    @report[:declared_adapters] << fqn if decision
    if java_class.kind == :enum
      @report[:enums] << fqn
      { 'type' => 'string' }
    elsif (block_kit = block_kit_type(java_class))
      map_to_swift(block_kit, "SlackBlockKit.#{block_kit}", 'SlackBlockKit')
    elsif java_class.top_level? && !fqn.start_with?(RESPONSE_PACKAGE)
      shared_ref(java_class)
    else
      inline_schema(java_class, inline_stack, where)
    end
  end

  # Schema for a type read through a Gson adapter, following its GsonAdapters decision.
  def adapter_schema(fqn, decision, where)
    case decision.kind
    when :swift
      map_to_swift(decision.swift.split('.').last, decision.swift, decision.module)
    when :schema
      handwritten_ref(decision.schema)
    when :untyped
      @report[:untyped_adapters] << fqn
      {}
    when :unsupported
      raise "#{where}: #{fqn} is read through a Gson adapter marked unsupported (#{decision.reason})"
    end
  end

  # SlackBlockKit type name for a Java Block Kit class, or nil when the class is not one.
  # A class nested in a model class that merely shares a Block Kit name (such as
  # AgentsConversationsListViewsResponse.View) is not a Block Kit type.
  def block_kit_type(java_class)
    return nil unless java_class.top_level? && BLOCK_KIT_PACKAGES.any? { |package| java_class.fqn.start_with?("#{package}.") }

    name = BLOCK_KIT_ALIASES.fetch(java_class.name, java_class.name)
    return name if @block_kit_types.include?(name)

    raise "#{java_class.fqn} is a Block Kit type without a SlackBlockKit counterpart"
  end

  def inline_schema(java_class, inline_stack, where)
    raise "#{where}: #{java_class.fqn} contains itself through inner classes" if inline_stack.include?(java_class)

    object_schema(java_class, inline_stack + [java_class])
  end
end
