# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'
require_relative 'java_test_support'
require_relative '../lib/java_openapi/class_index'
require_relative '../lib/java_openapi/type_overrides'

class TypeOverridesTest < Minitest::Test
  include JavaTestSupport

  KEY = 'com.example.Foo#count'

  def entry(**attributes)
    { 'type' => 'integer', 'java_type' => 'String', 'reason' => 'why', 'evidence' => ['fixture.json'] }.merge(attributes.transform_keys(&:to_s))
  end

  def overrides(attributes = entry, key: KEY)
    TypeOverrides.new({ key => attributes })
  end

  def assert_invalid(attributes, pattern, key: KEY)
    error = assert_raises(RuntimeError) { overrides(attributes, key: key) }
    assert_match pattern, error.message
  end

  def test_shape_validation
    assert_invalid entry(type: 'date'), /type must be one of/
    assert_invalid entry(type: nil), /type must be one of/
    assert_invalid entry(type: 'schema'), /needs `schema`/
    assert_invalid entry(reason: ''), /reason is missing/
    assert_invalid entry(evidence: []), /evidence is missing/
    assert_invalid entry(type: 'integer', added: true), /needs `type: schema`/
    assert_invalid entry(type: 'schema', schema: { 'type' => 'string' }, added: true), /added field has no java_type/
  end

  def test_error_message_names_source_and_key
    error = assert_raises(RuntimeError) { TypeOverrides.new({ KEY => entry(reason: nil) }, source: 'x.yml') }

    assert_equal "x.yml: #{KEY}: reason is missing", error.message
  end

  def test_valid_added_entry_and_entry_accessors
    added = overrides(entry(type: 'schema', schema: { 'type' => 'string' }, java_type: nil, added: true))
    result = added.entries.first

    assert_equal 'com.example.Foo', result.fqn
    assert_equal 'count', result.json_key
    assert result.added
  end

  def test_java_type_is_normalised_without_spaces
    assert_equal 'Map<String,Integer>', overrides(entry(java_type: 'Map<String, Integer>')).entries.first.java_type
  end

  def index
    write_java('com/example/Foo.java', <<~JAVA)
      package com.example;
      import com.google.gson.annotations.SerializedName;
      public class Foo {
        private String count;
        @SerializedName("renamed_key") private List<String> items;
      }
    JAVA
    build_index
  end

  def test_validate_passes_for_matching_field
    overrides.validate!(index)
    overrides(entry(java_type: 'List<String>'), key: 'com.example.Foo#renamed_key').validate!(index)
  end

  def test_validate_fails_on_missing_class
    error = assert_raises(RuntimeError) { overrides(entry, key: 'com.example.Gone#count').validate!(index) }
    assert_match(/class com\.example\.Gone no longer exists/, error.message)
  end

  def test_validate_fails_on_missing_field
    error = assert_raises(RuntimeError) { overrides(entry, key: 'com.example.Foo#nope').validate!(index) }
    assert_match(/no field with JSON key `nope`/, error.message)
  end

  def test_validate_fails_on_java_type_mismatch
    error = assert_raises(RuntimeError) { overrides(entry(java_type: 'Integer')).validate!(index) }
    assert_match(/java_type is `Integer` but the source declares `String`/, error.message)
  end

  def test_validate_fails_when_added_field_is_now_declared
    added = entry(type: 'schema', schema: {}, java_type: nil, added: true)
    error = assert_raises(RuntimeError) { overrides(added).validate!(index) }
    assert_match(/now declares `count`; remove `added`/, error.message)

    overrides(added, key: 'com.example.Foo#brand_new').validate!(index)
  end

  def owner_and_field
    foo = index.fully_qualified('com.example.Foo')
    [foo, foo.fields.first]
  end

  def test_apply_json_type
    owner, field = owner_and_field
    result = overrides.apply({ 'type' => 'string' }, owner, field, 'count')

    assert_equal 'integer', result['type']
    assert_equal 'string', result['x-java-type']
    assert_match(/`Foo\.count` is declared `String`, but recorded responses send integers\./, result['description'])
  end

  def test_apply_untyped_replaces_with_empty_schema_plus_metadata
    owner, field = owner_and_field
    result = overrides(entry(type: 'untyped')).apply({ 'type' => 'string' }, owner, field, 'count')

    assert_equal %w[description x-java-type], result.keys.sort
    assert_match(/values of another type/, result['description'])
  end

  def test_apply_schema_and_untyped_source
    owner, field = owner_and_field
    custom = { '$ref' => '#/components/schemas/Thing' }
    result = overrides(entry(type: 'schema', schema: custom)).apply({}, owner, field, 'count')

    assert_equal custom['$ref'], result['$ref']
    assert_equal 'untyped', result['x-java-type']
    refute custom.key?('description'), 'apply must not mutate the configured schema'
  end

  def test_apply_returns_schema_unchanged_without_entry
    owner, field = owner_and_field
    schema = { 'type' => 'string' }

    assert_same schema, overrides.apply(schema, owner, field, 'other')
  end

  def test_additions_for
    foo = index.fully_qualified('com.example.Foo')
    added = overrides(entry(type: 'schema', schema: { 'type' => 'string' }, java_type: nil, added: true), key: 'com.example.Foo#extra')
    additions = added.additions_for(foo)

    assert_equal ['extra'], additions.keys
    assert_equal 'string', additions['extra']['type']
    assert_match(/Not declared by java-slack-sdk `Foo`/, additions['extra']['description'])
  end

  def test_unused_keys
    owner, field = owner_and_field
    both = TypeOverrides.new({ KEY => entry, 'com.example.Foo#other' => entry })

    assert_equal [KEY, 'com.example.Foo#other'], both.unused_keys
    both.apply({ 'type' => 'string' }, owner, field, 'count')
    assert_equal ['com.example.Foo#other'], both.unused_keys
  end

  def test_load_reads_yaml
    path = File.join(java_dir, 'overrides.yml')
    File.write(path, { KEY => entry }.to_yaml)

    assert_equal [KEY], TypeOverrides.load(path).entries.map(&:key)
  end
end
