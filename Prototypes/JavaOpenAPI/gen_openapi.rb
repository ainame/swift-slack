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

require "json"
require "fileutils"
require "set"

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

MODIFIERS = Set["public", "private", "protected", "static", "final", "abstract", "transient", "volatile",
                "synchronized", "native", "default", "strictfp", "sealed", "non-sealed"]
CLASS_KINDS = %w[class interface enum record].freeze

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
  generic_unresolved: [],
}

# ---------------------------------------------------------------- tokenizer

# Strings, comments, identifiers, numbers and punctuation; whitespace is matched so it can be dropped.
TOKEN = %r{"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|//[^\n]*|/\*.*?\*/|[A-Za-z_$][A-Za-z0-9_$]*|\d[\w.]*|\.\.\.|->|::|[{}()\[\]<>;=,.@?&|:+\-*/!%^~]|\s+}m

def tokenize(source)
  source.scan(TOKEN).reject { |t| t.match?(/\A\s/) || t.start_with?("//", "/*") }
end

# ---------------------------------------------------------------- Java model

JFile = Struct.new(:path, :package, :imports, :classes) do
  def initialize(path)
    super(path, "", [], {})
  end
end

class JClass
  attr_reader :name, :kind, :outer, :file, :fields, :inner
  attr_accessor :extends

  def initialize(name, kind, outer, file)
    @name = name
    @kind = kind       # class / interface / enum / record
    @outer = outer     # enclosing JClass or nil
    @file = file
    @extends = nil     # raw superclass type string
    @fields = []       # [type_tokens, field_name, serialized_name_or_nil]
    @inner = {}        # name => JClass
  end

  def fqn
    outer ? "#{outer.fqn}.#{name}" : "#{file.package}.#{name}"
  end
end

# ---------------------------------------------------------------- parser

# Index just past the bracket that balances toks[i] (which must be `open`).
def skip_balanced(toks, i, open, close)
  depth = 0
  while i < toks.size
    if toks[i] == open
      depth += 1
    elsif toks[i] == close
      depth -= 1
      return i + 1 if depth.zero?
    end
    i += 1
  end
  i
end

# Splits a declaration header into [annotations, remaining tokens].
# Annotation arguments are kept as token lists.
def parse_annotations(header)
  annotations = {}
  rest = []
  i = 0
  while i < header.size
    if header[i] == "@" && i + 1 < header.size && header[i + 1] != "interface"
      j = i + 1
      name = header[j]
      j += 1
      while j + 1 < header.size && header[j] == "."
        name = header[j + 1]
        j += 2
      end
      args = []
      if j < header.size && header[j] == "("
        close = skip_balanced(header, j, "(", ")")
        args = header[j + 1...close - 1]
        j = close
      end
      annotations[name] = args
      i = j
    else
      rest << header[i]
      i += 1
    end
  end
  [annotations, rest]
end

def string_literals(tokens)
  tokens.select { |t| t.start_with?('"') }.map { |t| JSON.parse(t) }
end

# `extends A.B<C>` tokens => "A.B<C>"
def extends_clause(rest, ei)
  implements = rest[ei..].index("implements")
  stop = implements ? ei + implements : rest.size
  rest[ei + 1...stop].join(" ").gsub(" . ", ".").gsub(" < ", "<").gsub(" > ", ">")
end

# Which of class/interface/enum/record a member header declares (nil for fields and methods).
def declaration_kind(rest)
  CLASS_KINDS.find do |k|
    idx = rest.index(k)
    next false unless idx

    idx.zero? || MODIFIERS.include?(rest[idx - 1]) || rest[0...idx].all? { |t| MODIFIERS.include?(t) }
  end
end

# Parses a class body; `i` points just after the opening brace. Returns the index after the closing brace.
def parse_body(toks, i, cls)
  n = toks.size
  if cls.kind == "enum"
    # Constants are irrelevant; skip the whole body.
    depth = 1
    while i < n && depth.positive?
      depth += 1 if toks[i] == "{"
      depth -= 1 if toks[i] == "}"
      i += 1
    end
    return i
  end

  while i < n
    return i + 1 if toks[i] == "}"

    if toks[i] == ";"
      i += 1
      next
    end

    # Collect the member header up to `;`, `{` or `=` outside parentheses.
    start = i
    paren = 0
    while i < n
      t = toks[i]
      if t == "("
        paren += 1
      elsif t == ")"
        paren -= 1
      elsif paren.zero? && [";", "{", "="].include?(t)
        break
      end
      i += 1
    end
    header = toks[start...i]
    stop = toks[i]
    annotations, rest = parse_annotations(header)
    kind = declaration_kind(rest)
    kind = "annotation" if header.include?("@") && rest.include?("interface") && rest[0] == "interface"

    if stop == "{"
      if kind && kind != "annotation"
        ki = rest.index(kind)
        inner = JClass.new(rest[ki + 1], kind, cls, cls.file)
        inner.extends = extends_clause(rest, rest.index("extends")) if rest.include?("extends")
        cls.inner[inner.name] = inner
        i = parse_body(toks, i + 1, inner)
      else
        # annotation type, method, constructor or initializer block: skip it
        i = skip_balanced(toks, i, "{", "}")
      end
      next
    end

    if stop == "="
      # Skip the initializer up to the `;` at bracket depth 0.
      depth = 0
      while i < n
        t = toks[i]
        if ["(", "{", "["].include?(t)
          depth += 1
        elsif [")", "}", "]"].include?(t)
          depth -= 1
        elsif t == ";" && depth.zero?
          break
        end
        i += 1
      end
    end
    i += 1 # the `;`

    # Field (not abstract method, constant or transient state)?
    next if rest.include?("(")
    next if cls.kind == "interface" # interface fields are implicitly static final
    next if rest.any? { |t| %w[static final transient].include?(t) }

    body = rest.reject { |t| MODIFIERS.include?(t) }
    next if body.size < 2

    name = body.last
    type_tokens = body[0...-1]
    REPORT[:multi_declarator] << "#{cls.fqn}.#{name}" if top_level_comma?(type_tokens) # `int a, b;`

    serialized = nil
    if annotations.key?("SerializedName")
      serialized = string_literals(annotations["SerializedName"]).first
      REPORT[:alternate_names] << "#{cls.fqn}.#{name}" if annotations["SerializedName"].include?("alternate")
    end
    cls.fields << [type_tokens, name, serialized]
  end
  i
end

# Is there a comma outside generic brackets? (`Map<A, B>` has none; `int a, b` does.)
def top_level_comma?(tokens)
  depth = 0
  tokens.each do |t|
    case t
    when "<" then depth += 1
    when ">" then depth -= 1
    when "," then return true if depth.zero?
    end
  end
  false
end

# Reads tokens up to (not including) `;` and joins them: used for package/import names.
def read_name(toks, i)
  parts = []
  while toks.fetch(i) != ";"
    parts << toks[i]
    i += 1
  end
  [parts, i + 1]
end

def parse_file(path)
  toks = tokenize(File.read(path, encoding: "UTF-8"))
  jfile = JFile.new(path)
  i = 0
  n = toks.size
  while i < n
    case toks[i]
    when "package"
      parts, i = read_name(toks, i + 1)
      jfile.package = parts.join
    when "import"
      parts, i = read_name(toks, i + 1)
      jfile.imports << parts.join if !parts.empty? && parts[0] != "static"
    else
      start = i
      paren = 0
      while i < n && !(toks[i] == "{" && paren.zero?) && !(toks[i] == ";" && paren.zero?)
        paren += 1 if toks[i] == "("
        paren -= 1 if toks[i] == ")"
        i += 1
      end
      header = toks[start...i]
      if i >= n || toks[i] == ";"
        i += 1
        next
      end
      _, rest = parse_annotations(header)
      kind = CLASS_KINDS.find { |k| rest.include?(k) }
      if kind.nil?
        i = skip_balanced(toks, i, "{", "}")
        next
      end
      cls = JClass.new(rest[rest.index(kind) + 1], kind, nil, jfile)
      cls.extends = extends_clause(rest, rest.index("extends")) if rest.include?("extends") && kind == "class"
      jfile.classes[cls.name] = cls
      i = parse_body(toks, i + 1, cls)
    end
  end
  jfile
end

# ---------------------------------------------------------------- class index

INDEX = {}      # fqn of a top-level class => JClass
BY_PACKAGE = {} # package => { simple name => JClass }

def index_tree(root)
  Dir.glob("**/*.java", base: root).sort.each do |relative|
    next if File.basename(relative) == "package-info.java"

    begin
      jfile = parse_file(File.join(root, relative))
    rescue StandardError => e
      warn "PARSE FAIL #{relative} #{e.message}"
      next
    end
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

# ---------------------------------------------------------------- type resolution

# Parses Java type tokens into [name, [type args], array dimensions]. Raises IndexError on malformed input.
def split_type(tokens)
  pos = 0
  parse = lambda do
    if tokens.fetch(pos) == "?" # wildcard: `? extends X` => X, bare `?` => Object
      pos += 1
      if pos < tokens.size && %w[extends super].include?(tokens[pos])
        pos += 1
        next parse.call
      end
      next ["Object", [], 0]
    end

    name = tokens[pos]
    pos += 1
    while pos + 1 < tokens.size && tokens[pos] == "." && tokens[pos + 1] != "<"
      name += ".#{tokens[pos + 1]}"
      pos += 2
    end
    args = []
    if pos < tokens.size && tokens[pos] == "<"
      pos += 1
      until tokens.fetch(pos) == ">"
        args << parse.call
        pos += 1 if tokens.fetch(pos) == ","
      end
      pos += 1
    end
    dims = 0
    while pos + 1 < tokens.size && tokens[pos] == "[" && tokens[pos + 1] == "]"
      dims += 1
      pos += 2
    end
    if pos < tokens.size && tokens[pos] == "..."
      dims += 1
      pos += 1
    end
    [name, args, dims]
  end
  parse.call
end

def resolve_super(cls)
  return nil unless cls.extends

  resolve_class(cls, split_type(tokenize(cls.extends))[0], for_super: true)
end

# Inner class `name` visible from `cls`: own, superclass chain, then enclosing classes.
def lookup_inner(cls, name)
  seen = Set.new.compare_by_identity
  c = cls
  while c
    k = c
    while k && !seen.include?(k)
      seen << k
      return k.inner[name] if k.inner.key?(name)

      k = resolve_super(k)
    end
    c = c.outer
  end
  nil
end

# For `extends X`, where X may be an inner class of an enclosing class (but not of the class itself).
def lookup_inner_of_enclosing(cls, name)
  c = cls.outer
  while c
    return c.inner[name] if c.inner.key?(name)

    c = c.outer
  end
  nil
end

# Resolves a (possibly dotted) simple name used inside `ctx` to a JClass, or nil.
def resolve_class(ctx, name, for_super: false)
  parts = name.split(".")
  first = parts[0]
  base = nil
  unless for_super && first == ctx.name
    base = for_super ? lookup_inner_of_enclosing(ctx, first) : lookup_inner(ctx, first)
  end

  if base.nil?
    jfile = ctx.file
    # explicit imports (including imports of an inner class)
    jfile.imports.each do |import|
      next unless import.end_with?(".#{first}")

      base = INDEX[import]
      if base.nil?
        outer_name, _, inner_name = import.rpartition(".")
        outer = INDEX[outer_name]
        base = outer.inner[inner_name] if outer && outer.inner.key?(inner_name)
      end
      break if base
    end
    # same package
    base ||= BY_PACKAGE.fetch(jfile.package, {})[first]
    # wildcard imports
    if base.nil?
      jfile.imports.each do |import|
        next unless import.end_with?(".*")

        base = BY_PACKAGE.fetch(import[0...-2], {})[first]
        break if base
      end
    end
    # fully-qualified name
    if base.nil? && parts.size > 1
      (parts.size - 1).downto(1) do |k|
        if (found = INDEX[parts[0..k].join(".")])
          base = found
          parts = parts[k..]
          break
        end
      end
    end
  end
  return nil if base.nil?

  parts[1..].each do |part|
    base = base.inner[part]
    return nil if base.nil?
  end
  base
end

# Gson's default FieldNamingPolicy for this SDK: lowerCamel => lower_snake.
def snake(name)
  name.each_char.with_index.map { |ch, i| ch.match?(/\p{Lu}/) && i.positive? ? "_#{ch.downcase}" : ch.downcase }.join
end

# JSON key => [type tokens, field name, declaring class], inherited fields first.
def all_fields(cls, stack = [])
  fields = {}
  sup = resolve_super(cls)
  if sup && sup.kind == "class" && !stack.include?(sup)
    fields.merge!(all_fields(sup, stack + [cls]))
  elsif cls.extends && sup.nil?
    REPORT[:generic_unresolved] << "#{cls.fqn} extends #{cls.extends}"
  end
  cls.fields.each do |type_tokens, name, serialized|
    fields[serialized || snake(name)] = [type_tokens, name, cls]
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

def type_schema(tree, ctx, where, inline_stack)
  name, args, dims = tree
  short = name.split(".").last

  schema =
    if COLLECTIONS.include?(short)
      { "type" => "array", "items" => args.empty? ? {} : type_schema(args[0], ctx, where, inline_stack) }
    elsif MAPS.include?(short)
      value = args.size > 1 ? type_schema(args[1], ctx, where, inline_stack) : {}
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
      REPORT[:overrides_used] << "#{short} -> #{swift_type}"
      OVERRIDE_SCHEMAS[schema_name] = swift_type
      COMPONENTS[schema_name] ||= {}
      ref(schema_name)
    elsif UNTYPED_ADAPTER.include?(short)
      (REPORT[:untyped_adapter][short] ||= []) << where
      {}
    else
      cls = resolve_class(ctx, name)
      if cls.nil?
        note_unknown(name, where) unless %w[JsonObject JsonArray].include?(name)
        {}
      elsif cls.kind == "enum"
        REPORT[:enums] << cls.fqn
        { "type" => "string" }
      elsif shared_component?(cls) && cls.fqn.include?(".model.block") &&
            (BLOCKKIT_ALIASES.key?(short) || BLOCKKIT_PUBLIC.include?(short))
        target = BLOCKKIT_ALIASES.fetch(short, short)
        REPORT[:overrides_used] << "#{short} -> SlackBlockKit.#{target}"
        OVERRIDE_SCHEMAS[target] = "SlackBlockKit.#{target}"
        COMPONENTS[target] ||= {}
        ref(target)
      elsif shared_component?(cls)
        component_ref(cls)
      else
        inline_schema(cls, inline_stack, where)
      end
    end

  dims.times { schema = { "type" => "array", "items" => schema } }
  schema
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
  all_fields(cls).each do |key, (type_tokens, field_name, owner)|
    begin
      tree = split_type(type_tokens)
    rescue StandardError
      note_unknown(type_tokens.join(" "), "#{cls.fqn}.#{field_name}")
      properties[key] = {}
      next
    end
    stack = inline ? inline_stack : inline_stack + [cls]
    properties[key] = type_schema(tree, owner, "#{cls.fqn}.#{field_name}", stack)
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
