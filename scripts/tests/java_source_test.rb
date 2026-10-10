# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'java_test_support'
require_relative '../lib/java_openapi/java_source'

class JavaSourceTest < Minitest::Test
  include JavaTestSupport

  def test_package_and_imports
    file = parse_java(<<~JAVA)
      package com.example.model;

      import java.util.List;
      import com.other.*;
      import static java.util.Collections.emptyList;

      public class Foo {}
    JAVA

    assert_equal 'com.example.model', file.package
    assert_equal ['java.util.List', 'com.other.*'], file.imports
    assert_equal ['Foo'], file.classes.keys
    assert_equal 'com.example.model.Foo', file.classes['Foo'].fqn
  end

  def test_fields_with_serialized_names
    klass = parse_java(<<~JAVA).classes['Foo']
      package p;
      import com.google.gson.annotations.SerializedName;
      public class Foo {
        private String plainName;
        @SerializedName("custom_key") private Integer renamed;
        @SerializedName(value = "primary", alternate = {"alt1", "alt2"}) private Boolean multi;
      }
    JAVA

    assert_equal %w[plainName renamed multi], klass.fields.map(&:name)
    assert_equal ['plain_name', 'custom_key', 'primary'], klass.fields.map(&:json_key)
    assert_nil klass.fields[0].serialized_name
  end

  def test_static_and_transient_fields_are_skipped_but_final_instance_fields_kept
    klass = parse_java(<<~JAVA).classes['Foo']
      package p;
      public class Foo {
        public static final String TYPE_NAME = "message";
        public static final int LIMIT = 5;
        private static String shared;
        private transient String secret;
        private final String type = TYPE_NAME;
        private String kept;
      }
    JAVA

    assert_equal %w[type kept], klass.fields.map(&:name)
    assert_equal({ 'TYPE_NAME' => 'message' }, klass.constants)
  end

  def test_generic_and_array_types
    fields = parse_java(<<~JAVA).classes['Foo'].fields
      package p;
      import java.util.*;
      public class Foo {
        private Map<String, List<User>> byName;
        private String[] names;
        private int[][] grid;
        private List<? extends User> bounded;
        private List<?> anything;
        private java.util.Map<String, Integer> qualified;
      }
    JAVA
    types = fields.to_h { |field| [field.name, field.type] }

    assert_equal 'Map<String,List<User>>', types['byName'].to_s
    assert_equal 'Map', types['byName'].name
    assert_equal 'List<User>', types['byName'].args[1].to_s
    assert_equal 'String[]', types['names'].to_s
    assert_equal 2, types['grid'].dims
    assert_equal 'List<User>', types['bounded'].to_s
    assert_equal 'List<Object>', types['anything'].to_s
    assert_equal 'java.util.Map', types['qualified'].name
    assert_equal 'Map', types['qualified'].simple_name
  end

  def test_nested_classes_and_superclass
    klass = parse_java(<<~JAVA).classes['Outer']
      package p;
      public class Outer extends Base {
        private String a;
        public static class Inner {
          private String b;
          public static class Deep { private String c; }
        }
        public interface Marker {}
      }
    JAVA

    assert_equal 'Base', klass.superclass.name
    assert_equal %w[Inner Marker], klass.inner.keys
    assert_equal :interface, klass.inner['Marker'].kind
    deep = klass.inner['Inner'].inner['Deep']
    assert_equal 'p.Outer.Inner.Deep', deep.fqn
    assert_equal 'Outer.Inner.Deep', deep.nested_name
    refute deep.top_level?
    assert klass.top_level?
    assert_same klass, klass.inner['Inner'].outer
  end

  def test_methods_constructors_and_initializers_are_ignored
    klass = parse_java(<<~JAVA).classes['Foo']
      package p;
      public class Foo {
        // comment
        private String a;
        public Foo() {}
        public String getA() { return a; }
        static { }
        { }
      }
    JAVA

    assert_equal ['a'], klass.fields.map(&:name)
  end

  def test_enum_body_is_ignored
    klass = parse_java(<<~JAVA).classes['Color']
      package p;
      public enum Color {
        RED("r"), GREEN("g");
        private final String code;
        Color(String code) { this.code = code; }
      }
    JAVA

    assert_equal :enum, klass.kind
    assert_empty klass.fields
  end

  def test_syntax_error_raises_with_file_and_line
    path = write_java('Bad.java', "package p;\npublic class Bad {\n  private String ;\n}\n")
    error = assert_raises(RuntimeError) { JavaSource::FileParser.new(path).parse }

    assert_match(/Bad\.java:\d+: syntax error/, error.message)
  end

  def test_multiple_declarators_raise
    path = write_java('Multi.java', "package p;\npublic class Multi {\n  private String a, b;\n}\n")
    error = assert_raises(RuntimeError) { JavaSource::FileParser.new(path).parse }

    assert_match(/Multi\.java:3: multiple declarators/, error.message)
  end

  def test_snake_case
    assert_equal 'user_id', JavaSource.snake_case('userId')
    assert_equal 'ok', JavaSource.snake_case('ok')
    assert_equal 'is_i_m', JavaSource.snake_case('isIM')
    assert_equal 'team_i_d', JavaSource.snake_case('teamID')
  end
end
