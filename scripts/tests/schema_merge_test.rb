require 'minitest/autorun'
require_relative '../lib/schema_merge_policies'

class SchemaMergeTest < Minitest::Test
  STRING = { 'type' => 'string' }.freeze

  def object(properties, required = nil)
    schema = { 'type' => 'object', 'properties' => properties }
    schema['required'] = required if required
    schema
  end

  def merge(definitions, policies, handwritten: [])
    SchemaMerge.merge_all(definitions, policies: policies, handwritten: handwritten)
  end

  def test_union_keeps_properties_from_every_fixture_regardless_of_order
    definitions = {
      'a.list' => { 'Meta' => object({ 'next_cursor' => STRING, 'messages' => { 'type' => 'array', 'items' => STRING } }) },
      'z.update' => { 'Meta' => object({ 'messages' => { 'type' => 'array', 'items' => STRING } }) },
    }
    merged = merge(definitions, { 'Meta' => SchemaMergePolicy.union })

    assert_equal %w[next_cursor messages], merged.dig('Meta', 'properties').keys
  end

  def test_union_requires_only_properties_every_fixture_requires
    definitions = {
      'a' => { 'Meta' => object({ 'ok' => STRING, 'x' => STRING }, %w[ok x]) },
      'b' => { 'Meta' => object({ 'ok' => STRING, 'y' => STRING }, %w[ok y]) },
    }
    merged = merge(definitions, { 'Meta' => SchemaMergePolicy.union })

    assert_equal %w[ok], merged.dig('Meta', 'required')
  end

  def test_union_prefers_concrete_over_untyped_schemas
    untyped_array = { 'type' => 'array', 'items' => {} }
    strings = { 'type' => 'array', 'items' => STRING }
    policies = { 'Meta' => SchemaMergePolicy.union }

    [[untyped_array, strings], [strings, untyped_array]].each do |first, second|
      merged = merge({ 'a' => { 'Meta' => object({ 'warnings' => first }) },
                       'b' => { 'Meta' => object({ 'warnings' => second }) } }, policies)
      assert_equal strings, merged.dig('Meta', 'properties', 'warnings')
    end

    empty_object = object({})
    merged = merge({ 'a' => { 'Meta' => object({ 'extra' => empty_object }) },
                     'b' => { 'Meta' => object({ 'extra' => object({ 'id' => STRING }) }) } }, policies)
    assert_equal %w[id], merged.dig('Meta', 'properties', 'extra', 'properties').keys
  end

  def test_union_merges_nested_objects_and_array_items
    policies = { 'Meta' => SchemaMergePolicy.union }
    merged = merge({ 'a' => { 'Meta' => object({ 'list' => { 'type' => 'array', 'items' => object({ 'a' => STRING }) } }) },
                     'b' => { 'Meta' => object({ 'list' => { 'type' => 'array', 'items' => object({ 'b' => STRING }) } }) } }, policies)

    assert_equal %w[a b], merged.dig('Meta', 'properties', 'list', 'items', 'properties').keys
  end

  def test_union_fails_on_type_conflicts
    definitions = {
      'a.list' => { 'Meta' => object({ 'count' => { 'type' => 'integer' } }) },
      'b.list' => { 'Meta' => object({ 'count' => STRING }) },
    }
    error = assert_raises(SchemaMergeError) { merge(definitions, { 'Meta' => SchemaMergePolicy.union }) }

    assert_includes error.message, 'Meta.count'
    assert_includes error.message, 'a.list, b.list'
  end

  def test_union_rejects_non_object_against_object
    definitions = {
      'a' => { 'Properties' => { 'type' => 'string' } },
      'b' => { 'Properties' => object({ 'x' => STRING }) },
    }

    assert_raises(SchemaMergeError) { merge(definitions, { 'Properties' => SchemaMergePolicy.union }) }
  end

  def test_union_last_wins_fields_keep_the_last_fixture_schema
    definitions = {
      'a' => { 'Props' => object({ 'canvas' => { '$ref' => '#/A' }, 'id' => STRING }) },
      'b' => { 'Props' => object({ 'canvas' => { '$ref' => '#/B' }, 'name' => STRING }) },
    }
    merged = merge(definitions, { 'Props' => SchemaMergePolicy.union(last_wins: %w[canvas]) })

    assert_equal({ '$ref' => '#/B' }, merged.dig('Props', 'properties', 'canvas'))
    assert_equal %w[canvas id name], merged.dig('Props', 'properties').keys.sort
  end

  def test_unlisted_collision_fails_with_name_fixtures_and_keys
    definitions = {
      'a.list' => { 'Team' => object({ 'id' => STRING, 'name' => STRING }) },
      'b.list' => { 'Team' => object({ 'id' => STRING, 'domain' => STRING }) },
    }
    error = assert_raises(SchemaMergeError) { merge(definitions, {}) }

    assert_includes error.message, 'Team'
    assert_includes error.message, 'a.list, b.list'
    assert_includes error.message, 'differing keys: domain, name'
  end

  def test_identical_property_sets_and_handwritten_names_do_not_collide
    definitions = {
      'a' => { 'Same' => object({ 'id' => STRING }), 'Call' => object({ 'id' => STRING }) },
      'b' => { 'Same' => object({ 'id' => STRING }), 'Call' => object({}) },
    }

    merged = merge(definitions, {}, handwritten: %w[Call])
    assert_equal({}, merged.dig('Call', 'properties'))
  end

  def test_known_collision_keeps_last_definition
    definitions = {
      'a' => { 'Team' => object({ 'id' => STRING, 'name' => STRING }) },
      'b' => { 'Team' => object({ 'id' => STRING }) },
    }
    merged = merge(definitions, { 'Team' => SchemaMergePolicy.known_collision('#177') })

    assert_equal %w[id], merged.dig('Team', 'properties').keys
  end

  def test_policy_table_covers_properties_and_response_metadata
    assert_equal :union, MERGE_POLICIES.dig('Properties', :policy)
    assert_equal :union, MERGE_POLICIES.dig('ResponseMetadata', :policy)
    MERGE_POLICIES.each_value do |entry|
      next unless entry[:policy] == :known_collision

      assert_match(/\A#\d+\z/, entry[:issue])
    end
  end
end
