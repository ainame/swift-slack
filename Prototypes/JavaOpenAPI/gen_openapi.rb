#!/usr/bin/env ruby
# frozen_string_literal: true

# Prototype: emit OpenAPI 3.1 response schemas from java-slack-sdk Java sources.
#
# Usage:
#   gen_openapi.rb <java-slack-sdk dir> <out openapi.json> <out config.yaml> method [method...]
#
# Environment:
#   SLACKBLOCKKIT_DIR  directory of swift-slack's hand-written SlackBlockKit sources. Block-kit
#                      classes whose simple name matches a public type there become typeOverrides.
#   TREE_SITTER_JAVA_LIB  path of the compiled tree-sitter-java grammar. Defaults to the output of
#                      `make tree-sitter-java` (.tmp/tree-sitter-java/ in the repository root).
#
# Java -> OpenAPI rules:
#   * Every `<Method>Response` class under com.slack.api.methods.response is a path's 200 schema.
#   * Top-level classes of com.slack.api.model become shared `$ref` components; nested (inner)
#     classes are emitted inline at the use site.
#   * Everything is optional except `ok` (Gson leaves absent fields null).
#   * Property names follow Gson: @SerializedName value if present, else snake_case of the field name.
#     Superclass fields come first.
#   * Gson TypeAdapter types that swift-slack hand-writes (Block, View, TextObject, ...) are emitted
#     as empty component schemas and mapped to SlackBlockKit types through `typeOverrides`.
#   * Enums become strings; unknown/untyped Java types become `{}` and are listed in gen-report.json.
#
# The Java sources are read with a tree-sitter syntax tree (see "Java parsing" below), so the
# script only has to say which tree nodes it cares about.

require "json"
require "fileutils"
require "set"
require "tree_sitter"

sdk_dir, out_path, out_config_path, *methods = ARGV
abort "usage: #{$PROGRAM_NAME} <java-slack-sdk dir> <out openapi.json> <out config.yaml> method..." if methods.empty?

MODEL_ROOT = File.join(sdk_dir, "slack-api-model/src/main/java")
CLIENT_ROOT = File.join(sdk_dir, "slack-api-client/src/main/java")
RESPONSE_PKG = "com.slack.api.methods.response"

# Java TypeAdapter types that swift-slack hand-writes in SlackBlockKit.
# Java simple name => [schema name, Swift type for typeOverrides]
OVERRIDES = {
  "LayoutBlock" => ["Block", "SlackBlockKit.Block"],
  "View" => ["View", "SlackBlockKit.View"],
  "TextObject" => ["TextObject", "SlackBlockKit.TextObject"],
}.freeze
# Java subtypes collapsed onto a SlackBlockKit supertype.
BLOCKKIT_ALIASES = { "PlainTextObject" => "TextObject", "MarkdownTextObject" => "TextObject" }.freeze
# Gson TypeAdapter types without a SlackBlockKit counterpart: left untyped.
UNTYPED_ADAPTER = Set["ContextBlockElement", "ContextActionsBlockElement", "BlockElement", "RichTextElement"]

COLLECTIONS = Set["List", "Set", "Collection", "ArrayList", "Iterable", "LinkedList"]
MAPS = Set["Map", "HashMap", "LinkedHashMap", "TreeMap"]
STRING = Set["String", "CharSequence", "Instant", "Date", "UUID"]
INTEGER = Set["Integer", "int", "Long", "long", "Short", "short", "BigInteger", "Byte", "byte"]
NUMBER = Set["Double", "double", "Float", "float", "Number", "BigDecimal"]
BOOLEAN = Set["Boolean", "boolean"]
UNTYPED = Set["Object", "JsonElement"]
# Types outside the parsed sources that are left untyped (`{}`), as written in the Java source.
# Anything else that cannot be resolved to a parsed class is an error.
EXTERNAL_UNTYPED = Set["JsonObject", "JsonArray"] # Gson trees: arbitrary JSON, silently `{}`
EXTERNAL_UNTYPED_REPORTED = Set["InputStream"]    # java.io stream (binary file download): `{}`, listed in gen-report.json

# Things we could not model faithfully; written to gen-report.json.
REPORT = {
  unknown_types: {},
  untyped_adapter: {},
  overrides_used: Set.new,
  cycles: [],
  enums: Set.new,
  unsupported_declarators: [],
  alternate_names: [],
  multi_declarator: [],
  name_collisions: [],
  generic_unresolved: [], # always empty now (an unresolvable superclass raises); kept so gen-report.json keeps its shape
}

# ---------------------------------------------------------------- Java model

# One .java file: its package, its imports (as written, `a.b.C` or `a.b.*`) and its top-level classes.
JFile = Struct.new(:path, :package, :imports, :classes)

# A declared Java type. `Map<String, List<User>>[]` is name "Map", args [String, List<User>], dims 1.
# `name` may be dotted (`Outer.Inner`, `java.util.Map`). `line` is where it is written, for error messages.
JType = Struct.new(:name, :args, :dims, :line) do
  def short
    name.split(".").last
  end
end

# A serialisable instance field. `serialized_name` is the @SerializedName value, if there is one.
JField = Struct.new(:name, :type, :serialized_name)

class JClass
  attr_reader :name, :kind, :outer, :file, :fields, :inner
  attr_accessor :superclass

  def initialize(name, kind, outer, file)
    @name = name
    @kind = kind        # "class", "interface" or "enum"
    @outer = outer      # enclosing JClass or nil
    @file = file
    @superclass = nil   # JType of the `extends` clause (classes only)
    @fields = []        # [JField]
    @inner = {}         # name => JClass
  end

  def fqn
    outer ? "#{outer.fqn}.#{name}" : "#{file.package}.#{name}"
  end
end

# ---------------------------------------------------------------- Java parsing

# tree-sitter turns Java source into a tree of nodes; `node.type` is the grammar rule (:class_declaration,
# :field_declaration, ...), `node.child_by_field_name("name")` picks a named part of a node, and
# `node.each_named` walks its children (punctuation and keywords are "anonymous" and skipped).
# Print a tree for any Java file with `tree-sitter parse File.java` to see what it looks like.
GRAMMAR_PATH = ENV.fetch("TREE_SITTER_JAVA_LIB") do
  extension = RbConfig::CONFIG["host_os"].include?("darwin") ? "dylib" : "so"
  default = File.expand_path("../../.tmp/tree-sitter-java/libtree-sitter-java.#{extension}", __dir__)
  abort "tree-sitter-java grammar not built: run `make tree-sitter-java` in the repository root" unless File.exist?(default)
  default
end
JAVA_PARSER = TreeSitter::Parser.new.tap { |parser| parser.language = TreeSitter::Language.load("java", GRAMMAR_PATH) }

DECLARATION_KINDS = {
  class_declaration: "class",
  interface_declaration: "interface",
  enum_declaration: "enum",
}.freeze
COMMENTS = %i[line_comment block_comment].freeze
# Class members that never contribute JSON properties.
SKIPPED_MEMBERS = (%i[method_declaration constructor_declaration compact_constructor_declaration
                      static_initializer block constant_declaration annotation_type_declaration] + COMMENTS).freeze
# Gson ignores static and transient fields; `final` ones are constants in these model classes.
NON_PROPERTY_MODIFIERS = %i[static final transient].freeze

# Parses one .java file into a JFile. Raises (with file:line) on syntax errors and on Java constructs
# this generator does not understand, instead of silently producing a partial model.
class JavaFileParser
  def initialize(path)
    @path = path
    @source = File.read(path, encoding: "UTF-8")
  end

  def parse
    root = JAVA_PARSER.parse_string(nil, @source).root_node
    fail_at(find_error(root), "syntax error") if root.has_error?

    file = JFile.new(@path, "", [], {})
    root.each_named do |node|
      case node.type
      when :package_declaration
        file.package = qualified_name(node.named_child(0))
      when :import_declaration
        import = parse_import(node)
        file.imports << import if import
      when *DECLARATION_KINDS.keys
        cls = parse_class(node, nil, file)
        file.classes[cls.name] = cls
      when :annotation_type_declaration, *COMMENTS
        next # `@interface` declarations hold no model fields
      else
        fail_at(node, "unsupported top-level declaration `#{node.type}`")
      end
    end
    file
  end

  private

  # `import a.b.C;` => "a.b.C", `import a.b.*;` => "a.b.*", `import static ...;` => nil (not a type import).
  def parse_import(node)
    return nil if node.each.any? { |child| child.type == :static }

    name = qualified_name(node.named_child(0))
    node.each.any? { |child| child.type == :asterisk } ? "#{name}.*" : name
  end

  def parse_class(node, outer, file)
    cls = JClass.new(text(node.child_by_field_name("name")), DECLARATION_KINDS.fetch(node.type), outer, file)
    if (superclass = node.child_by_field_name("superclass"))
      cls.superclass = parse_type(superclass.named_child(0))
    end
    # Enum constants are irrelevant for JSON schemas, so the body of an enum is not read at all.
    parse_members(node.child_by_field_name("body"), cls) unless cls.kind == "enum"
    cls
  end

  def parse_members(body, cls)
    body.each_named do |member|
      case member.type
      when :field_declaration
        cls.fields.concat(parse_field_declaration(member, cls))
      when *DECLARATION_KINDS.keys
        inner = parse_class(member, cls, cls.file)
        cls.inner[inner.name] = inner
      when *SKIPPED_MEMBERS
        next
      else
        fail_at(member, "unsupported member `#{member.type}` in #{cls.fqn}")
      end
    end
  end

  # `private @SerializedName("a_b") List<String> aB, c;` => [JField(aB), JField(c)]
  def parse_field_declaration(node, cls)
    modifiers = node.each_named.find { |child| child.type == :modifiers }
    return [] if modifiers && (modifier_keywords(modifiers) & NON_PROPERTY_MODIFIERS).any?

    declarators = node.each_named.select { |child| child.type == :variable_declarator }
    REPORT[:multi_declarator] << "#{cls.fqn}.#{field_name(declarators.first)}" if declarators.size > 1

    declared_type = parse_type(node.child_by_field_name("type"))
    declarators.map do |declarator|
      name = field_name(declarator)
      type = declared_type
      if (dimensions = declarator.child_by_field_name("dimensions")) # C-style `String names[]`
        REPORT[:unsupported_declarators] << "#{cls.fqn}.#{name}"
        type = JType.new(type.name, type.args, type.dims + text(dimensions).count("["), type.line)
      end
      JField.new(name, type, serialized_name(modifiers, "#{cls.fqn}.#{name}"))
    end
  end

  def field_name(declarator)
    text(declarator.child_by_field_name("name"))
  end

  # Keyword modifiers (`:private`, `:static`, ...) of a `modifiers` node; annotations are separate.
  def modifier_keywords(modifiers)
    modifiers.each.map(&:type)
  end

  # The key from `@SerializedName("key")` or `@SerializedName(value = "key", alternate = {...})`, or nil.
  def serialized_name(modifiers, where)
    return nil unless modifiers

    annotation = modifiers.each_named.find do |child|
      %i[annotation marker_annotation].include?(child.type) && text(child.child_by_field_name("name")).end_with?("SerializedName")
    end
    return nil unless annotation

    arguments = annotation.child_by_field_name("arguments")
    fail_at(annotation, "@SerializedName without a name") unless arguments

    name = nil
    arguments.each_named do |argument|
      if argument.type == :string_literal
        name = string_value(argument) # @SerializedName("key")
      elsif argument.type == :element_value_pair
        case text(argument.child_by_field_name("key"))
        when "value" then name = string_value(argument.child_by_field_name("value"))
        when "alternate" then REPORT[:alternate_names] << where # extra accepted keys; not modelled
        end
      end
    end
    fail_at(annotation, "@SerializedName without a name") unless name
    name
  end

  def string_value(literal)
    JSON.parse(text(literal)) # Java string literals are JSON-compatible for the plain names used here
  end

  # Converts a type node into a JType. Wildcards (`? extends X`, `? super X`) become X, a bare `?` Object.
  def parse_type(node)
    case node.type
    when :type_identifier, :scoped_type_identifier, :integral_type, :floating_point_type, :boolean_type
      JType.new(qualified_name(node), [], 0, line_of(node)) # `String`, `Outer.Inner`, `int`
    when :generic_type # `Map<String, X>`: the type, then its type_arguments
      base, arguments = node.each_named.to_a
      JType.new(parse_type(base).name, arguments.each_named.map { |argument| parse_type(argument) }, 0, line_of(node))
    when :array_type # `X[][]`: an element type plus a `dimensions` node
      element = parse_type(node.child_by_field_name("element"))
      JType.new(element.name, element.args, element.dims + text(node.child_by_field_name("dimensions")).count("["), element.line)
    when :wildcard
      bound = node.each_named.first
      bound ? parse_type(bound) : JType.new("Object", [], 0, line_of(node))
    else
      fail_at(node, "unsupported type `#{node.type}`")
    end
  end

  def line_of(node)
    node.start_point.row + 1
  end

  def text(node)
    @source.byteslice(node.start_byte...node.end_byte)
  end

  # Source text of a (possibly dotted) name without whitespace.
  def qualified_name(node)
    text(node).gsub(/\s+/, "")
  end

  # Deepest node that tree-sitter flagged as an error or as missing.
  def find_error(node)
    return node if node.error? || node.missing?

    node.each_named { |child| return find_error(child) if child.has_error? }
    node
  end

  def fail_at(node, message)
    raise "#{@path}:#{node.start_point.row + 1}: #{message}"
  end
end

# ---------------------------------------------------------------- class index

INDEX = {}      # fqn of a top-level class => JClass
BY_PACKAGE = {} # package => { simple name => JClass }

def index_tree(root)
  Dir.glob("**/*.java", base: root).sort.each do |relative|
    next if File.basename(relative) == "package-info.java"

    jfile = JavaFileParser.new(File.join(root, relative)).parse
    jfile.classes.each_value do |cls|
      INDEX[cls.fqn] = cls
      (BY_PACKAGE[jfile.package] ||= {})[cls.name] = cls
    end
  end
end

index_tree(File.join(MODEL_ROOT, "com/slack/api/model"))
index_tree(File.join(CLIENT_ROOT, "com/slack/api/methods/response"))
index_tree(File.join(MODEL_ROOT, "com/slack/api/util")) # best effort

# Public type names of swift-slack's SlackBlockKit module.
BLOCKKIT_PUBLIC = Set.new
if (blockkit_dir = ENV["SLACKBLOCKKIT_DIR"]) && !blockkit_dir.empty?
  Dir.glob("**/*.swift", base: blockkit_dir).sort.each do |relative|
    File.read(File.join(blockkit_dir, relative), encoding: "UTF-8").scan(/^public (?:struct|enum|class) (\w+)/) do |(name)|
      BLOCKKIT_PUBLIC << name
    end
  end
end

# ---------------------------------------------------------------- name resolution

# Resolves a (possibly dotted) type name as written inside class `ctx` to a JClass, or nil.
# The first segment is looked up with the five steps below, in this order (a simplified javac):
#   1. nested classes of ctx, then of each enclosing class;
#   2. explicit single-type imports (`import a.b.Foo;`);
#   3. the same package;
#   4. wildcard imports (`import a.b.*;`);
#   5. a fully-qualified name (`a.b.Foo`, `a.b.Outer.Inner`).
# Any further segments select nested classes: `Outer.Inner.Deeper`.
def resolve_class(ctx, name)
  first, *rest = name.split(".")
  base = nested_class(ctx, first) ||
         single_import(ctx.file, first) ||
         same_package_class(ctx.file, first) ||
         wildcard_import(ctx.file, first)
  return select_nested(base, rest) if base

  fully_qualified_class(name.split("."))
end

# Superclass of `cls` (`extends X`), resolved like any other type name. Raises if it cannot be found.
def resolve_super(cls)
  return nil unless cls.superclass

  resolve_class(cls, cls.superclass.name) or
    raise "#{cls.file.path}:#{cls.superclass.line}: cannot resolve superclass `#{cls.superclass.name}` of #{cls.fqn}"
end

# Step 1: a class called `name` nested in `cls`, or in the class around it, and so on outwards.
# Nested classes inherited from superclasses are not considered.
def nested_class(cls, name)
  while cls
    return cls.inner[name] if cls.inner.key?(name)

    cls = cls.outer
  end
  nil
end

# Step 2: `import a.b.Foo;` names the class `Foo` exactly.
def single_import(file, name)
  file.imports.each do |import|
    found = INDEX[import] if import.end_with?(".#{name}")
    return found if found
  end
  nil
end

# Step 3: a top-level class of the file's own package.
def same_package_class(file, name)
  BY_PACKAGE.fetch(file.package, {})[name]
end

# Step 4: `import a.b.*;` makes every top-level class of package a.b visible.
def wildcard_import(file, name)
  file.imports.each do |import|
    next unless import.end_with?(".*")

    found = BY_PACKAGE.fetch(import[0...-2], {})[name]
    return found if found
  end
  nil
end

# Step 5: `a.b.Outer.Inner` => the class Inner of the top-level class a.b.Outer (longest known class prefix wins).
def fully_qualified_class(parts)
  parts.size.downto(2) do |length|
    outer = INDEX[parts.first(length).join(".")]
    return select_nested(outer, parts.drop(length)) if outer
  end
  nil
end

# `Outer` + ["Inner", "Deeper"] => Outer.Inner.Deeper, or nil if a segment is not a nested class.
def select_nested(klass, names)
  names.reduce(klass) { |current, name| current&.inner&.[](name) }
end

# ---------------------------------------------------------------- fields

# Gson's default FieldNamingPolicy for this SDK: lowerCamel => lower_snake.
def snake(name)
  name.each_char.with_index.map { |ch, i| ch.match?(/\p{Lu}/) && i.positive? ? "_#{ch.downcase}" : ch.downcase }.join
end

# JSON key => [JField, declaring class], inherited fields first.
def all_fields(cls, stack = [])
  fields = {}
  sup = resolve_super(cls)
  if sup && sup.kind == "class" && !stack.include?(sup)
    fields.merge!(all_fields(sup, stack + [cls]))
  end
  cls.fields.each do |field|
    fields[field.serialized_name || snake(field.name)] = [field, cls]
  end
  fields
end

# ---------------------------------------------------------------- schema emission

COMPONENTS = {}        # schema name => schema
COMPONENT_SOURCE = {}  # schema name => fqn of the Java class
OVERRIDE_SCHEMAS = {}  # schema name => Swift type, for typeOverrides

# Top-level model classes (not response classes) become shared components.
def shared_component?(cls)
  cls.outer.nil? && !cls.fqn.start_with?(RESPONSE_PKG)
end

def note_unknown(type_name, where)
  (REPORT[:unknown_types][type_name] ||= []) << where
end

def ref(name)
  { "$ref" => "#/components/schemas/#{name}" }
end

# OpenAPI schema for a JType used inside class `ctx` (`where` names the field, for the report).
def type_schema(type, ctx, where, inline_stack)
  short = type.short

  schema =
    if COLLECTIONS.include?(short)
      { "type" => "array", "items" => type.args.empty? ? {} : type_schema(type.args[0], ctx, where, inline_stack) }
    elsif MAPS.include?(short)
      value = type.args.size > 1 ? type_schema(type.args[1], ctx, where, inline_stack) : {}
      { "type" => "object", "additionalProperties" => value.empty? ? true : value }
    elsif STRING.include?(short)
      { "type" => "string" }
    elsif INTEGER.include?(short)
      { "type" => "integer" }
    elsif NUMBER.include?(short)
      { "type" => "number" }
    elsif BOOLEAN.include?(short)
      { "type" => "boolean" }
    elsif UNTYPED.include?(short)
      {}
    elsif OVERRIDES.key?(short)
      schema_name, swift_type = OVERRIDES[short]
      override_ref(short, schema_name, swift_type)
    elsif UNTYPED_ADAPTER.include?(short)
      (REPORT[:untyped_adapter][short] ||= []) << where
      {}
    else
      class_schema(type, ctx, where, inline_stack)
    end

  type.dims.times { schema = { "type" => "array", "items" => schema } }
  schema
end

# Schema for a type that is (hopefully) one of the parsed Java classes.
def class_schema(type, ctx, where, inline_stack)
  cls = resolve_class(ctx, type.name)
  if cls.nil?
    if EXTERNAL_UNTYPED_REPORTED.include?(type.name)
      note_unknown(type.name, where)
    elsif !EXTERNAL_UNTYPED.include?(type.name)
      raise "#{ctx.file.path}:#{type.line}: cannot resolve type `#{type.name}` (#{where})"
    end
    {}
  elsif cls.kind == "enum"
    REPORT[:enums] << cls.fqn
    { "type" => "string" }
  elsif shared_component?(cls) && cls.fqn.include?(".model.block") &&
        (BLOCKKIT_ALIASES.key?(type.short) || BLOCKKIT_PUBLIC.include?(type.short))
    target = BLOCKKIT_ALIASES.fetch(type.short, type.short)
    override_ref(type.short, target, "SlackBlockKit.#{target}")
  elsif shared_component?(cls)
    component_ref(cls)
  else
    inline_schema(cls, inline_stack, where)
  end
end

# `$ref` to an empty placeholder schema that the generator config maps onto a hand-written Swift type.
def override_ref(java_name, schema_name, swift_type)
  REPORT[:overrides_used] << "#{java_name} -> #{swift_type}"
  OVERRIDE_SCHEMAS[schema_name] = swift_type
  COMPONENTS[schema_name] ||= {}
  ref(schema_name)
end

# `$ref` to a shared component, emitting it on first use. Same-named classes from different packages
# get a package suffix.
def component_ref(cls)
  schema_name = cls.name
  if COMPONENT_SOURCE.key?(schema_name) && COMPONENT_SOURCE[schema_name] != cls.fqn
    REPORT[:name_collisions] << "#{schema_name}: #{COMPONENT_SOURCE[schema_name]} vs #{cls.fqn}"
    schema_name = "#{cls.name}_#{cls.file.package.split(".").last}"
  end
  unless COMPONENT_SOURCE.key?(schema_name)
    COMPONENT_SOURCE[schema_name] = cls.fqn
    COMPONENTS[schema_name] = nil # reserve the name first so recursive types terminate
    COMPONENTS[schema_name] = object_schema(cls, [], schema_name)
  end
  ref(schema_name)
end

def inline_schema(cls, inline_stack, where)
  if inline_stack.include?(cls)
    REPORT[:cycles] << "#{cls.fqn} (at #{where})"
    return {}
  end
  object_schema(cls, inline_stack + [cls], where, inline: true)
end

# Every property is optional; `required` is only passed for the `ok` of a response.
def object_schema(cls, inline_stack, where, required: nil, inline: false)
  properties = {}
  all_fields(cls).each do |key, (field, owner)|
    stack = inline ? inline_stack : inline_stack + [cls]
    properties[key] = type_schema(field.type, owner, "#{cls.fqn}.#{field.name}", stack)
  end
  schema = { "type" => "object", "properties" => properties }
  schema["required"] = required if required && !required.empty?
  schema
end

# ---------------------------------------------------------------- main

def response_class(method)
  class_name = "#{method.split(".").map { |p| p[0].upcase + p[1..] }.join}Response"
  INDEX.each_value.find { |c| c.fqn.start_with?(RESPONSE_PKG) && c.name == class_name }
end

def operation_id(method)
  first, *rest = method.split(".")
  first + rest.map { |p| p[0].upcase + p[1..] }.join
end

paths = {}
methods.each do |method|
  cls = response_class(method)
  if cls.nil?
    warn "NO RESPONSE CLASS #{method}"
    next
  end
  COMPONENTS[cls.name] = object_schema(cls, [], cls.name, required: ["ok"])
  COMPONENT_SOURCE[cls.name] = cls.fqn
  paths["/#{method}"] = {
    "post" => {
      "operationId" => operation_id(method),
      "responses" => { "200" => { "description" => "OK",
                                  "content" => { "application/json" => { "schema" => ref(cls.name) } } } },
    },
  }
end

document = {
  "openapi" => "3.1.0",
  "info" => { "title" => "Slack Web API (java-slack-sdk derived prototype)", "version" => "0.0.0" },
  "paths" => paths,
  "components" => { "schemas" => COMPONENTS.sort_by { |name, _| name }.to_h },
}
File.write(out_path, JSON.pretty_generate(document))

# swift-openapi-generator config; typeOverrides point the placeholder schemas at SlackBlockKit.
config = +"generate:\n  - types\naccessModifier: public\nnamingStrategy: idiomatic\n"
unless OVERRIDE_SCHEMAS.empty?
  config << "additionalImports:\n  - SlackBlockKit\n"
  config << "typeOverrides:\n  schemas:\n"
  OVERRIDE_SCHEMAS.sort.each { |name, swift_type| config << "    #{name}: #{swift_type}\n" }
end
File.write(out_config_path, config)

report = REPORT.transform_values { |v| v.is_a?(Set) ? v.sort : v }
report[:named_schemas] = COMPONENTS.keys.sort
File.write(File.join(File.dirname(out_path), "gen-report.json"), JSON.pretty_generate(report))
puts "schemas: #{COMPONENTS.size} paths: #{paths.size}"
