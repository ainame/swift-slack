# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'tree_sitter'

# Reads upstream java-slack-sdk sources into a small model of files, classes and fields.
#
# tree-sitter turns Java source into a tree of nodes: `node.type` is the grammar rule (:class_declaration,
# :field_declaration, ...), `node.child_by_field_name("name")` picks a named part of a node, and
# `node.each_named` walks its children (punctuation and keywords are "anonymous" and skipped).
# `tree-sitter parse File.java` prints the tree of any file.
module JavaSource
  # One .java file: its package, its imports (as written, `a.b.C` or `a.b.*`) and its top-level classes.
  JavaFile = Struct.new(:path, :package, :imports, :classes)

  # A declared type. `Map<String, List<User>>[]` is name "Map", args [String, List<User>], dims 1.
  # `name` may be dotted (`Outer.Inner`, `java.util.Map`); `line` is where it is written, for errors.
  JavaType = Struct.new(:name, :args, :dims, :line) do
    def simple_name
      name.split('.').last
    end

    # Source text without spaces, e.g. `Map<String,List<User>>[]`.
    def to_s
      arguments = args.empty? ? '' : "<#{args.join(',')}>"
      "#{name}#{arguments}#{'[]' * dims}"
    end
  end

  # An instance field that Gson serializes. `serialized_name` is the @SerializedName value, if any.
  JavaField = Struct.new(:name, :type, :serialized_name) do
    # Gson's naming for this SDK: @SerializedName if present, otherwise lowerCamel => lower_snake.
    def json_key
      serialized_name || JavaSource.snake_case(name)
    end
  end

  # A class, interface or enum, possibly nested in another class.
  class JavaClass
    attr_reader :name, :kind, :outer, :file, :fields, :inner, :constants
    attr_accessor :superclass

    def initialize(name, kind, outer, file)
      @name = name
      @kind = kind        # :class, :interface or :enum
      @outer = outer      # enclosing JavaClass, or nil for a top-level class
      @file = file
      @superclass = nil   # JavaType of the `extends` clause
      @fields = []        # [JavaField]
      @inner = {}         # simple name => JavaClass
      @constants = {}     # `static final String NAME = "literal"` => { "NAME" => "literal" }
    end

    def fqn
      outer ? "#{outer.fqn}.#{name}" : "#{file.package}.#{name}"
    end

    # `Outer.Inner` for a nested class, `Name` for a top-level one.
    def nested_name
      fqn.delete_prefix("#{file.package}.")
    end

    def top_level?
      outer.nil?
    end
  end

  module_function

  # lowerCamel => lower_snake, the FieldNamingPolicy java-slack-sdk configures for Gson.
  def snake_case(name)
    name.each_char.with_index.map do |char, index|
      char.match?(/\p{Lu}/) && index.positive? ? "_#{char.downcase}" : char.downcase
    end.join
  end

  # The compiled tree-sitter-java grammar (`make tree-sitter-java`), overridable with TREE_SITTER_JAVA_LIB.
  def grammar_path
    ENV.fetch('TREE_SITTER_JAVA_LIB') do
      extension = RbConfig::CONFIG['host_os'].include?('darwin') ? 'dylib' : 'so'
      path = File.expand_path("../../../.tmp/tree-sitter-java/libtree-sitter-java.#{extension}", __dir__)
      raise 'tree-sitter-java grammar is not built: run `make tree-sitter-java`' unless File.exist?(path)

      path
    end
  end

  def parser
    @parser ||= TreeSitter::Parser.new.tap do |parser|
      parser.language = TreeSitter::Language.load('java', grammar_path)
    end
  end

  # Parses one .java file into a JavaFile. Raises with file:line on syntax errors and on Java constructs
  # that are not modelled, instead of silently producing a partial model.
  class FileParser
    DECLARATION_KINDS = {
      class_declaration: :class,
      interface_declaration: :interface,
      enum_declaration: :enum,
    }.freeze
    COMMENTS = %i[line_comment block_comment].freeze
    # Class members that never hold JSON properties.
    SKIPPED_MEMBERS = (%i[method_declaration constructor_declaration compact_constructor_declaration
                          static_initializer block constant_declaration annotation_type_declaration] + COMMENTS).freeze
    # Gson skips static and transient fields. Final instance fields are serialized (event `type` fields).
    NON_PROPERTY_MODIFIERS = %i[static transient].freeze

    def initialize(path)
      @path = path
      @source = File.read(path, encoding: 'UTF-8')
    end

    def parse
      root = JavaSource.parser.parse_string(nil, @source).root_node
      fail_at(find_error(root), 'syntax error') if root.has_error?

      file = JavaFile.new(@path, '', [], {})
      root.each_named do |node|
        case node.type
        when :package_declaration
          file.package = qualified_name(node.named_child(0))
        when :import_declaration
          import = parse_import(node)
          file.imports << import if import
        when *DECLARATION_KINDS.keys
          java_class = parse_class(node, nil, file)
          file.classes[java_class.name] = java_class
        when :annotation_type_declaration, *COMMENTS
          next # `@interface` declarations hold no model fields
        else
          fail_at(node, "unsupported top-level declaration `#{node.type}`")
        end
      end
      file
    end

    private

    # `import a.b.C;` => "a.b.C", `import a.b.*;` => "a.b.*", `import static ...;` => nil (not a type).
    def parse_import(node)
      return nil if node.each.any? { |child| child.type == :static }

      name = qualified_name(node.named_child(0))
      node.each.any? { |child| child.type == :asterisk } ? "#{name}.*" : name
    end

    def parse_class(node, outer, file)
      java_class = JavaClass.new(text(node.child_by_field_name('name')), DECLARATION_KINDS.fetch(node.type), outer, file)
      if (superclass = node.child_by_field_name('superclass'))
        java_class.superclass = parse_type(superclass.named_child(0))
      end
      # Enum constants are irrelevant for JSON schemas, so an enum body is not read.
      parse_members(node.child_by_field_name('body'), java_class) unless java_class.kind == :enum
      java_class
    end

    def parse_members(body, java_class)
      body.each_named do |member|
        case member.type
        when :field_declaration
          parse_field_declaration(member, java_class)
        when *DECLARATION_KINDS.keys
          inner = parse_class(member, java_class, java_class.file)
          java_class.inner[inner.name] = inner
        when *SKIPPED_MEMBERS
          next
        else
          fail_at(member, "unsupported member `#{member.type}` in #{java_class.fqn}")
        end
      end
    end

    # `private @SerializedName("a_b") List<String> aB;` adds JavaField(aB) to the class;
    # `public static final String TYPE_NAME = "message";` adds a constant instead.
    def parse_field_declaration(node, java_class)
      modifiers = node.each_named.find { |child| child.type == :modifiers }
      keywords = modifiers ? modifiers.each.map(&:type) : []
      declarators = node.each_named.select { |child| child.type == :variable_declarator }
      fail_at(node, "multiple declarators in one field declaration in #{java_class.fqn}") if declarators.size > 1

      declarator = declarators.first
      name = text(declarator.child_by_field_name('name'))
      if (keywords & NON_PROPERTY_MODIFIERS).any?
        record_constant(java_class, name, declarator) if keywords.include?(:static) && keywords.include?(:final)
        return
      end
      fail_at(declarator, "C-style array declarator `#{name}[]` in #{java_class.fqn}") if declarator.child_by_field_name('dimensions')

      type = parse_type(node.child_by_field_name('type'))
      java_class.fields << JavaField.new(name, type, serialized_name(modifiers))
    end

    # Keeps `static final` fields initialised with a string literal, such as an event's TYPE_NAME.
    def record_constant(java_class, name, declarator)
      value = declarator.child_by_field_name('value')
      java_class.constants[name] = string_value(value) if value&.type == :string_literal
    end

    # The key from `@SerializedName("key")` or `@SerializedName(value = "key", alternate = {...})`, or nil.
    # Alternate keys are accepted by Gson when reading but are not modelled.
    def serialized_name(modifiers)
      return nil unless modifiers

      annotation = modifiers.each_named.find do |child|
        %i[annotation marker_annotation].include?(child.type) &&
          text(child.child_by_field_name('name')).end_with?('SerializedName')
      end
      return nil unless annotation

      arguments = annotation.child_by_field_name('arguments')
      name = arguments&.each_named&.filter_map do |argument|
        if argument.type == :string_literal
          string_value(argument)
        elsif argument.type == :element_value_pair && text(argument.child_by_field_name('key')) == 'value'
          string_value(argument.child_by_field_name('value'))
        end
      end&.first
      fail_at(annotation, '@SerializedName without a name') unless name
      name
    end

    # Java string literals in these sources are plain names, which are valid JSON strings.
    def string_value(literal)
      JSON.parse(text(literal))
    end

    # Converts a type node into a JavaType. `? extends X` and `? super X` become X, a bare `?` Object.
    def parse_type(node)
      case node.type
      when :type_identifier, :scoped_type_identifier, :integral_type, :floating_point_type, :boolean_type
        JavaType.new(qualified_name(node), [], 0, line_of(node))
      when :generic_type
        base, arguments = node.each_named.to_a
        JavaType.new(parse_type(base).name, arguments.each_named.map { |argument| parse_type(argument) }, 0, line_of(node))
      when :array_type
        element = parse_type(node.child_by_field_name('element'))
        dimensions = text(node.child_by_field_name('dimensions')).count('[')
        JavaType.new(element.name, element.args, element.dims + dimensions, element.line)
      when :wildcard
        bound = node.each_named.first
        bound ? parse_type(bound) : JavaType.new('Object', [], 0, line_of(node))
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

    # Source text of a possibly dotted name, without whitespace.
    def qualified_name(node)
      text(node).gsub(/\s+/, '')
    end

    # The deepest node that tree-sitter flagged as an error or as missing.
    def find_error(node)
      return node if node.error? || node.missing?

      node.each_named { |child| return find_error(child) if child.has_error? }
      node
    end

    def fail_at(node, message)
      raise "#{@path}:#{line_of(node)}: #{message}"
    end
  end
end
