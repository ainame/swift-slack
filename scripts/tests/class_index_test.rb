# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'java_test_support'
require_relative '../lib/java_openapi/class_index'

class ClassIndexTest < Minitest::Test
  include JavaTestSupport

  def test_nested_class_wins_over_everything_and_enclosing_classes_are_searched
    write_java('a/Outer.java', <<~JAVA)
      package a;
      public class Outer {
        public static class User {}
        public static class Inner { private User u; }
      }
    JAVA
    write_java('a/User.java', 'package a; public class User {}')
    index = build_index
    inner = index.fully_qualified('a.Outer.Inner')

    assert_equal 'a.Outer.User', index.resolve(inner, 'User').fqn
    assert_equal 'a.Outer.User', index.resolve(index.fully_qualified('a.Outer'), 'User').fqn
  end

  def test_single_import_beats_same_package_and_wildcard
    write_java('a/Foo.java', 'package a; import b.Thing; import c.*; public class Foo {}')
    write_java('a/Thing.java', 'package a; public class Thing {}')
    write_java('b/Thing.java', 'package b; public class Thing {}')
    write_java('c/Thing.java', 'package c; public class Thing {}')
    index = build_index

    assert_equal 'b.Thing', index.resolve(index.fully_qualified('a.Foo'), 'Thing').fqn
  end

def test_single_import_of_a_nested_class
  write_java('a/Foo.java', 'package a; import b.Outer.Inner; public class Foo {}')
  write_java('a/Inner.java', 'package a; public class Inner {}')
  write_java('b/Outer.java', 'package b; public class Outer { public static class Inner {} }')
  index = build_index

  assert_equal 'b.Outer.Inner', index.resolve(index.fully_qualified('a.Foo'), 'Inner').fqn
end

  def test_same_package_beats_wildcard_import
    write_java('a/Foo.java', 'package a; import c.*; public class Foo {}')
    write_java('a/Thing.java', 'package a; public class Thing {}')
    write_java('c/Thing.java', 'package c; public class Thing {}')
    index = build_index

    assert_equal 'a.Thing', index.resolve(index.fully_qualified('a.Foo'), 'Thing').fqn
  end

  def test_wildcard_import
    write_java('a/Foo.java', 'package a; import c.*; public class Foo {}')
    write_java('c/Only.java', 'package c; public class Only {}')
    index = build_index

    assert_equal 'c.Only', index.resolve(index.fully_qualified('a.Foo'), 'Only').fqn
    assert_nil index.resolve(index.fully_qualified('a.Foo'), 'Missing')
  end

  def test_fully_qualified_and_dotted_names
    write_java('a/Foo.java', 'package a; public class Foo {}')
    write_java('b/Outer.java', <<~JAVA)
      package b;
      public class Outer { public static class Inner { public static class Deep {} } }
    JAVA
    index = build_index
    foo = index.fully_qualified('a.Foo')

    assert_equal 'b.Outer', index.resolve(foo, 'b.Outer').fqn
    assert_equal 'b.Outer.Inner.Deep', index.resolve(foo, 'b.Outer.Inner.Deep').fqn
    assert_nil index.resolve(foo, 'b.Outer.Nope')
    assert_nil index.resolve(foo, 'java.util.List')
  end

  def test_outer_inner_dotted_name_via_import
    write_java('a/Foo.java', 'package a; import b.Outer; public class Foo {}')
    write_java('b/Outer.java', 'package b; public class Outer { public static class Inner {} }')
    index = build_index

    assert_equal 'b.Outer.Inner', index.resolve(index.fully_qualified('a.Foo'), 'Outer.Inner').fqn
  end

  def test_lookup_helpers
    write_java('a/Foo.java', 'package a; public class Foo {}')
    write_java('b/Foo.java', 'package b; public class Foo {}')
    write_java('a/package-info.java', 'package a;')
    index = build_index

    assert_equal %w[a.Foo b.Foo], index.classes_named('Foo').map(&:fqn).sort
    assert_equal ['Foo'], index.package_classes('a').keys
    assert_empty index.package_classes('zzz')
  end

  def test_add_tree_requires_existing_directory
    assert_raises(RuntimeError) { ClassIndex.new.add_tree(File.join(java_dir, 'missing')) }
  end

  def test_fields_of_puts_superclass_fields_first_and_subclass_overrides_by_key
    write_java('a/Base.java', 'package a; public class Base { private String id; private String shared; }')
    write_java('a/Mid.java', 'package a; public class Mid extends Base { private String mid; }')
    write_java('a/Leaf.java', <<~JAVA)
      package a;
      public class Leaf extends Mid { private String leaf; private Integer shared; }
    JAVA
    index = build_index
    fields = index.fields_of(index.fully_qualified('a.Leaf'))

    assert_equal %w[id shared mid leaf], fields.keys
    field, owner = fields['shared']
    assert_equal 'Integer', field.type.to_s
    assert_equal 'Leaf', owner.name
    assert_equal 'Base', fields['id'][1].name
  end

  def test_fields_of_ignores_interface_superclasses
    write_java('a/Marker.java', 'package a; public interface Marker { String x = ""; }')
    write_java('a/Foo.java', 'package a; public class Foo extends Marker { private String a; }')
    index = build_index

    assert_equal ['a'], index.fields_of(index.fully_qualified('a.Foo')).keys
  end

  def test_superclass_of
    write_java('a/Base.java', 'package a; public class Base {}')
    write_java('a/Foo.java', 'package a; public class Foo extends Base {}')
    index = build_index

    assert_equal 'a.Base', index.superclass_of(index.fully_qualified('a.Foo')).fqn
    assert_nil index.superclass_of(index.fully_qualified('a.Base'))
  end

  def test_superclass_of_raises_when_unresolvable
    write_java('a/Foo.java', "package a;\npublic class Foo extends Unknown {}\n")
    index = build_index
    error = assert_raises(RuntimeError) { index.superclass_of(index.fully_qualified('a.Foo')) }

    assert_match(/Foo\.java:2: cannot resolve superclass `Unknown` of a\.Foo/, error.message)
    assert_raises(RuntimeError) { index.fields_of(index.fully_qualified('a.Foo')) }
  end
end
