# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/java_openapi/fixture_placeholders'

class FixturePlaceholdersTest < Minitest::Test
  DOCUMENT = {
    'components' => {
      'schemas' => {
        'Root' => {
          'type' => 'object',
          'properties' => {
            'width' => { 'type' => 'integer', 'x-java-type' => 'string' },
            'ratio' => { 'type' => 'number', 'x-java-type' => 'number' },
            'name' => { 'type' => 'string' },
            'view' => { '$ref' => '#/components/schemas/View' },
            'blocks' => { 'type' => 'array', 'items' => { '$ref' => '#/components/schemas/Block' } },
            'files' => { 'type' => 'array', 'items' => { '$ref' => '#/components/schemas/File' } },
            'by_id' => { 'type' => 'object', 'additionalProperties' => { '$ref' => '#/components/schemas/File' } },
            'either' => { 'oneOf' => [{ 'type' => 'string' }, { '$ref' => '#/components/schemas/File' }] },
          },
        },
        'File' => { 'type' => 'object', 'properties' => { 'original_w' => { 'type' => 'integer', 'x-java-type' => 'string' } } },
        'View' => {},
        'Block' => {},
      },
    },
  }.freeze

  def preprocess(payload, schema = { '$ref' => '#/components/schemas/Root' })
    preprocessor = FixturePlaceholders::Preprocessor.new(DOCUMENT)
    [preprocessor.call(payload, schema), preprocessor.counts]
  end

  def fix_block_kit(payload)
    result, counts = preprocess({ 'view' => payload })
    [result['view'], counts]
  end

  def test_removes_recorder_placeholder_at_overridden_property
    result, counts = preprocess({ 'width' => '', 'name' => '' })

    assert_equal({ 'name' => '' }, result)
    assert_equal 1, counts.removed
  end

  def test_keeps_real_values_at_overridden_property
    result, counts = preprocess({ 'width' => 640, 'ratio' => 12.3 })

    assert_equal({ 'width' => 640, 'ratio' => 12.3 }, result)
    assert_equal 0, counts.removed
  end

  def test_removes_placeholders_in_nested_arrays_maps_and_refs
    payload = { 'files' => [{ 'original_w' => '' }, { 'original_w' => 5 }], 'by_id' => { 'F1' => { 'original_w' => '' } } }
    result, counts = preprocess(payload)

    assert_equal [{}, { 'original_w' => 5 }], result['files']
    assert_equal({ 'F1' => {} }, result['by_id'])
    assert_equal 2, counts.removed
  end

  def test_unknown_keys_and_scalars_pass_through
    result, counts = preprocess({ 'extra' => { 'original_w' => '' }, 'name' => 'x' })

    assert_equal({ 'extra' => { 'original_w' => '' }, 'name' => 'x' }, result)
    assert_equal 0, counts.removed
  end

  def test_one_of_picks_alternative_by_json_type
    string_result, = preprocess({ 'either' => 'html' })
    object_result, counts = preprocess({ 'either' => { 'original_w' => '' } })

    assert_equal({ 'either' => 'html' }, string_result)
    assert_equal({ 'either' => {} }, object_result)
    assert_equal 1, counts.removed
  end

  def test_one_of_without_matching_alternative_is_untyped
    result, = preprocess({ 'either' => [1, 2] })
    assert_equal({ 'either' => [1, 2] }, result)
  end

  def test_block_kit_url_placeholder
    result, counts = fix_block_kit({ 'type' => 'image', 'image_url' => '', 'title_url' => 'https://real.example/x' })

    assert_equal({ 'type' => 'image', 'image_url' => 'https://example.com', 'title_url' => 'https://real.example/x' }, result)
    assert_equal 1, counts.block_kit
  end

  def test_block_kit_text_object_type
    result, = fix_block_kit({ 'type' => 'section', 'text' => { 'type' => '', 'text' => 'hi' } })
    assert_equal 'plain_text', result['text']['type']

    # `type` is only fixed on objects that look like a text object (have `text` and `type`).
    result, = fix_block_kit({ 'type' => '', 'other' => 1 })
    assert_equal '', result['type']
  end

  def test_block_kit_styles
    list, = fix_block_kit({ 'type' => 'rich_text_list', 'style' => '' })
    button, counts = fix_block_kit({ 'type' => 'button', 'style' => '' })
    kept, = fix_block_kit({ 'type' => 'button', 'style' => 'primary' })

    assert_equal 'bullet', list['style']
    refute button.key?('style')
    assert_equal 1, counts.block_kit
    assert_equal 'primary', kept['style']
  end

  def test_block_kit_conversation_filter_include
    result, counts = fix_block_kit({ 'filter' => { 'include' => [''], 'exclude_bot_users' => false } })

    assert_equal [], result['filter']['include']
    assert_equal 1, counts.block_kit

    result, counts = fix_block_kit({ 'filter' => { 'include' => ['im', '', 'public'] } })
    assert_equal %w[im public], result['filter']['include']
    assert_equal 1, counts.block_kit
  end

  def test_block_kit_overflow_without_options_gets_empty_list
    result, counts = fix_block_kit({ 'type' => 'overflow' })
    with_options, = fix_block_kit({ 'type' => 'overflow', 'options' => [{ 'value' => 'a' }] })

    assert_equal({ 'type' => 'overflow', 'options' => [] }, result)
    assert_equal 1, counts.block_kit
    assert_equal [{ 'value' => 'a' }], with_options['options']
  end

  def test_block_kit_fixes_apply_through_arrays_of_blocks
    payload = { 'blocks' => [{ 'type' => 'section', 'accessory' => { 'type' => 'image', 'image_url' => '' } }] }
    result, = preprocess(payload)

    assert_equal 'https://example.com', result['blocks'][0]['accessory']['image_url']
  end

  def test_block_kit_fixes_do_not_apply_outside_empty_schemas
    result, = preprocess({ 'name' => '', 'files' => [{ 'image_url' => '' }] })
    assert_equal [{ 'image_url' => '' }], result['files']
  end

  def test_original_payload_is_not_mutated
    payload = { 'view' => { 'type' => 'image', 'image_url' => '' }, 'width' => '' }
    original = Marshal.load(Marshal.dump(payload))
    preprocess(payload)

    assert_equal original, payload
  end

  def test_helper_predicates
    assert FixturePlaceholders.matches_type?(3.0, 'integer')
    refute FixturePlaceholders.matches_type?(3.5, 'integer')
    assert FixturePlaceholders.matches_type?(nil, nil)
    assert FixturePlaceholders.placeholder?('integer', 123)
    refute FixturePlaceholders.placeholder?('integer', 124)
    assert FixturePlaceholders.placeholder?('number', 12.3)
    refute FixturePlaceholders.placeholder?('object', {})
  end

  def test_parse_accepts_duplicate_keys_and_deep_nesting
    assert_equal({ 'a' => 2 }, FixturePlaceholders.parse('{"a":1,"a":2}'))
    deep = ('[' * 200) + (']' * 200)
    assert_kind_of Array, FixturePlaceholders.parse(deep)
  end
  def test_one_of_picks_the_alternative_that_fits_array_elements
    document = { 'components' => { 'schemas' => {
      'Block' => {},
      'Value' => { 'oneOf' => [
        { 'type' => 'array', 'items' => { 'type' => 'string' } },
        { 'type' => 'array', 'items' => { '$ref' => '#/components/schemas/Block' } },
      ] },
    } } }
    preprocessor = FixturePlaceholders::Preprocessor.new(document)
    blocks = [{ 'type' => 'image', 'image_url' => '', 'alt_text' => 'x' }]

    fixed = preprocessor.call(blocks, { '$ref' => '#/components/schemas/Value' })

    assert_equal 'https://example.com', fixed.first['image_url']
    assert_equal %w[a b], preprocessor.call(%w[a b], { '$ref' => '#/components/schemas/Value' })
  end
end
