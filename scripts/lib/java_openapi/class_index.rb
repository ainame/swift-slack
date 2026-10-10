# frozen_string_literal: true

require_relative 'java_source'

# All parsed classes, with javac-like resolution of the type names written in them.
class ClassIndex
  def initialize
    @by_fqn = {}     # fqn of a top-level class => JavaSource::JavaClass
    @by_package = {} # package => { simple name => JavaSource::JavaClass }
  end

  # Parses every .java file under `root` (recursively) and adds its top-level classes.
  def add_tree(root)
    raise "#{root} does not exist" unless Dir.exist?(root)

    Dir.glob('**/*.java', base: root).sort.each do |relative|
      next if File.basename(relative) == 'package-info.java'

      file = JavaSource::FileParser.new(File.join(root, relative)).parse
      file.classes.each_value { |java_class| add(java_class) }
    end
    self
  end

  def add(java_class)
    @by_fqn[java_class.fqn] = java_class
    (@by_package[java_class.file.package] ||= {})[java_class.name] = java_class
  end

  # Top-level classes with simple name `name`, in any package.
  def classes_named(name)
    @by_fqn.values.select { |java_class| java_class.name == name }
  end

  # Top-level classes of `package`, by simple name.
  def package_classes(package)
    @by_package.fetch(package, {})
  end

  # Resolves a possibly dotted type name written inside class `context` to a class, or nil.
  # The first segment is looked up in this order, a simplified version of javac's rules:
  #   1. classes nested in `context`, then in each enclosing class;
  #   2. single-type imports (`import a.b.Foo;`);
  #   3. the same package;
  #   4. wildcard imports (`import a.b.*;`);
  #   5. a fully qualified name (`a.b.Foo`, `a.b.Outer.Inner`).
  # Further segments select nested classes: `Outer.Inner.Deeper`.
  def resolve(context, name)
    first, *rest = name.split('.')
    base = nested_class(context, first) ||
           single_import(context.file, first) ||
           same_package_class(context.file, first) ||
           wildcard_import(context.file, first)
    return select_nested(base, rest) if base

    fully_qualified(name)
  end

  # The superclass of `java_class`, or nil when it has none. Raises when it cannot be resolved.
  def superclass_of(java_class)
    return nil unless java_class.superclass

    resolve(java_class, java_class.superclass.name) or
      raise "#{java_class.file.path}:#{java_class.superclass.line}: " \
            "cannot resolve superclass `#{java_class.superclass.name}` of #{java_class.fqn}"
  end

  # `a.b.Outer.Inner` => the class Inner nested in the top-level class a.b.Outer. The longest known
  # top-level class prefix wins.
  def fully_qualified(name)
    parts = name.split('.')
    parts.size.downto(2) do |length|
      outer = @by_fqn[parts.first(length).join('.')]
      return select_nested(outer, parts.drop(length)) if outer
    end
    nil
  end

  # JSON key => [JavaField, declaring class] of every serialized field, inherited fields first.
  def fields_of(java_class, visiting = [])
    fields = {}
    superclass = superclass_of(java_class)
    if superclass&.kind == :class && !visiting.include?(superclass)
      fields.merge!(fields_of(superclass, visiting + [java_class]))
    end
    java_class.fields.each { |field| fields[field.json_key] = [field, java_class] }
    fields
  end

  private

  # Step 1: a class called `name` nested in `java_class`, or in the class around it, and so on outwards.
  # Nested classes inherited from superclasses are not considered.
  def nested_class(java_class, name)
    while java_class
      return java_class.inner[name] if java_class.inner.key?(name)

      java_class = java_class.outer
    end
    nil
  end

  # Step 2: `import a.b.Foo;` names the class `Foo` exactly.
  def single_import(file, name)
    file.imports.each do |import|
      found = @by_fqn[import] if import.end_with?(".#{name}")
      return found if found
    end
    nil
  end

  # Step 3: a top-level class of the file's own package.
  def same_package_class(file, name)
    package_classes(file.package)[name]
  end

  # Step 4: `import a.b.*;` makes every top-level class of package a.b visible.
  def wildcard_import(file, name)
    file.imports.each do |import|
      next unless import.end_with?('.*')

      found = package_classes(import.delete_suffix('.*'))[name]
      return found if found
    end
    nil
  end

  # `Outer` + ["Inner", "Deeper"] => Outer.Inner.Deeper, or nil if a segment is not a nested class.
  def select_nested(java_class, names)
    names.reduce(java_class) { |current, name| current&.inner&.[](name) }
  end
end
