# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'java_test_support'
require_relative '../lib/java_openapi/schema_builder'
require_relative '../lib/java_openapi/type_overrides'

class SchemaBuilderTest < Minitest::Test
  include JavaTestSupport

  MODEL = 'com.example.model'
  RESPONSE = 'com.slack.api.methods.response.things'

  def java(package, name, body, imports: [])
    write_java("#{package.tr('.', '/')}/#{name}.java",
               "package #{package};\n#{imports.map { |i| "import #{i};\n" }.join}public class #{name} #{body}")
  end

  def builder(type_overrides: TypeOverrides.new({}), handwritten: {}, block_kit: Set.new)
    SchemaBuilder.new(build_index, type_overrides: type_overrides, handwritten_schemas: handwritten,
                                   block_kit_types: block_kit)
  end

  def root(builder, fqn)
    builder.send(:instance_variable_get, :@index).fully_qualified(fqn)
  end

  def test_add_root_with_scalars_collections_and_maps
    java(MODEL, 'Thing', <<~BODY)
      {
        private String name;
        private Integer count;
        private long big;
        private Double ratio;
        private boolean flag;
        private List<String> tags;
        private String[] parts;
        private Map<String, Integer> counts;
        private Map<String, Object> anything;
        private Object raw;
        private JsonElement tree;
      }
    BODY
    b = builder
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))
    props = schema['properties']

    assert_equal 'object', schema['type']
    assert_equal({ 'type' => 'string' }, props['name'])
    assert_equal({ 'type' => 'integer' }, props['count'])
    assert_equal({ 'type' => 'integer' }, props['big'])
    assert_equal({ 'type' => 'number' }, props['ratio'])
    assert_equal({ 'type' => 'boolean' }, props['flag'])
    assert_equal({ 'type' => 'array', 'items' => { 'type' => 'string' } }, props['tags'])
    assert_equal({ 'type' => 'array', 'items' => { 'type' => 'string' } }, props['parts'])
    assert_equal({ 'type' => 'object', 'additionalProperties' => { 'type' => 'integer' } }, props['counts'])
    assert_equal({ 'type' => 'object', 'additionalProperties' => true }, props['anything'])
    assert_equal({}, props['raw'])
    assert_equal({}, props['tree'])
    refute schema.key?('required')
    assert_equal ['Thing'], b.components.keys
  end

  def test_property_names_follow_serialized_name_and_snake_case_with_superclass_first
    java(MODEL, 'Base', '{ private String baseId; }')
    java(MODEL, 'Thing', <<~BODY, imports: ['com.google.gson.annotations.SerializedName'])
      extends Base { @SerializedName("custom") private String other; private String userName; }
    BODY
    b = builder
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))

    assert_equal %w[base_id custom user_name], schema['properties'].keys
  end

  def test_required_keys
    java(RESPONSE, 'ThingResponse', '{ private boolean ok; private String error; }')
    b = builder
    schema = b.add_root('ThingResponse', root(b, "#{RESPONSE}.ThingResponse"), required: ['ok'])

    assert_equal ['ok'], schema['required']
  end

  def test_missing_required_key_raises
    java(RESPONSE, 'ThingResponse', '{ private String error; }')
    b = builder
    error = assert_raises(RuntimeError) { b.add_root('ThingResponse', root(b, "#{RESPONSE}.ThingResponse"), required: %w[ok type]) }

    assert_match(/has no ok, type field to require/, error.message)
  end

  def test_shared_top_level_model_becomes_ref_component_once
    java(MODEL, 'User', '{ private String id; }')
    java(MODEL, 'Thing', '{ private User first; private List<User> all; private Map<String, User> byId; }')
    b = builder
    props = b.add_root('Thing', root(b, "#{MODEL}.Thing"))['properties']
    ref = { '$ref' => '#/components/schemas/User' }

    assert_equal ref, props['first']
    assert_equal ref, props['all']['items']
    assert_equal ref, props['by_id']['additionalProperties']
    assert_equal %w[Thing User], b.components.keys
    assert_equal({ 'type' => 'string' }, b.components['User']['properties']['id'])
  end

  def test_recursive_shared_model_terminates
    java(MODEL, 'Node', '{ private Node parent; private List<Node> children; }')
    b = builder
    b.add_root('Holder', root(b, "#{MODEL}.Node"))

    # The root's own class is already named Holder, so self references point at it.
    holder = { '$ref' => '#/components/schemas/Holder' }
    assert_equal holder, b.components['Holder']['properties']['parent']
    assert_equal holder, b.components['Holder']['properties']['children']['items']
    assert_equal ['Holder'], b.components.keys
  end

  def test_inner_classes_are_inlined_and_same_named_inner_classes_do_not_collide
    java(MODEL, 'A', '{ private Item item; public static class Item { private String a; } }')
    java(MODEL, 'B', '{ private Item item; public static class Item { private Integer b; } }')
    b = builder
    a = b.add_root('A', root(b, "#{MODEL}.A"))
    bb = b.add_root('B', root(b, "#{MODEL}.B"))

    assert_equal %w[a], a['properties']['item']['properties'].keys
    assert_equal %w[b], bb['properties']['item']['properties'].keys
    assert_equal %w[A B], b.components.keys
  end

  def test_response_package_classes_are_inlined_not_shared
    java(RESPONSE, 'InnerResponse', '{ private String x; }')
    java(RESPONSE, 'OuterResponse', '{ private InnerResponse nested; }')
    b = builder
    schema = b.add_root('OuterResponse', root(b, "#{RESPONSE}.OuterResponse"))

    assert_equal ['x'], schema['properties']['nested']['properties'].keys
    assert_equal ['OuterResponse'], b.components.keys
  end

  def test_inner_class_containing_itself_raises
    java(MODEL, 'Loop', '{ private Part part; public static class Part { private Part again; } }')
    b = builder

    assert_raises(RuntimeError) { b.add_root('Loop', root(b, "#{MODEL}.Loop")) }.then do |error|
      assert_match(/contains itself through inner classes/, error.message)
    end
  end

  def test_enums_become_strings_and_are_reported
    java(MODEL, 'Thing', '{ private Kind kind; public enum Kind { ONE, TWO } }')
    b = builder
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))

    assert_equal({ 'type' => 'string' }, schema['properties']['kind'])
    assert_equal ["#{MODEL}.Thing.Kind"], b.report[:enums].to_a
  end

  def test_unknown_type_raises_with_location
    java(MODEL, 'Thing', "{\n  private Mystery m;\n}")
    b = builder
    error = assert_raises(RuntimeError) { b.add_root('Thing', root(b, "#{MODEL}.Thing")) }

    assert_match(/Thing\.java:\d+ .*cannot resolve type `Mystery`/, error.message)
  end

  def test_raw_collection_and_raw_map_raise
    java(MODEL, 'RawList', '{ private List items; }')
    java(MODEL, 'RawMap', '{ private Map<String> items; }')
    b = builder

    assert_match(/raw collection/, assert_raises(RuntimeError) { b.add_root('RawList', root(b, "#{MODEL}.RawList")) }.message)
    assert_match(/raw map/, assert_raises(RuntimeError) { b.add_root('RawMap', root(b, "#{MODEL}.RawMap")) }.message)
  end

  def test_block_kit_classes_map_to_placeholders
    java('com.slack.api.model.view', 'View', '{ private String id; }')
    java('com.slack.api.model.block', 'SectionBlock', '{ private String text; }')
    java('com.slack.api.model.block.composition', 'PlainTextObject', '{ }')
    java(MODEL, 'Thing', '{ private View view; private List<SectionBlock> blocks; }',
         imports: ['com.slack.api.model.view.View', 'com.slack.api.model.block.*'])
    java(MODEL, 'Texty', '{ private PlainTextObject text; }', imports: ['com.slack.api.model.block.composition.PlainTextObject'])
    b = builder(block_kit: Set['View', 'SectionBlock', 'TextObject'])
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))
    texty = b.add_root('Texty', root(b, "#{MODEL}.Texty"))

    assert_equal({ '$ref' => '#/components/schemas/View' }, schema['properties']['view'])
    assert_equal({ '$ref' => '#/components/schemas/SectionBlock' }, schema['properties']['blocks']['items'])
    assert_equal({ '$ref' => '#/components/schemas/TextObject' }, texty['properties']['text'])
    assert_equal({}, b.components['View'])
    assert_equal({ 'SectionBlock' => 'SlackBlockKit.SectionBlock', 'TextObject' => 'SlackBlockKit.TextObject',
                   'View' => 'SlackBlockKit.View' }, b.type_mappings)
    assert_equal ['SlackBlockKit'], b.mapped_modules.to_a
  end

  def test_block_kit_class_without_swift_counterpart_raises
    java('com.slack.api.model.block', 'NewBlock', '{ }')
    java(MODEL, 'Thing', '{ private NewBlock b; }', imports: ['com.slack.api.model.block.NewBlock'])
    b = builder(block_kit: Set['View'])

    assert_match(/without a SlackBlockKit counterpart/,
                 assert_raises(RuntimeError) { b.add_root('Thing', root(b, "#{MODEL}.Thing")) }.message)
  end

  def test_nested_class_named_like_block_kit_type_is_not_block_kit
    java(MODEL, 'Thing', '{ private View view; public static class View { private String id; } }')
    b = builder(block_kit: Set['View'])
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))

    assert_equal ['id'], schema['properties']['view']['properties'].keys
    assert_empty b.type_mappings
  end

  def test_gson_adapter_decisions_apply_by_fqn
    java('com.slack.api.model.block', 'LayoutBlock', '{ }')
    java(MODEL, 'Thing', '{ private List<LayoutBlock> blocks; }', imports: ['com.slack.api.model.block.LayoutBlock'])
    b = builder(block_kit: Set['Block'])
    schema = b.add_root('Thing', root(b, "#{MODEL}.Thing"))

    assert_equal({ '$ref' => '#/components/schemas/Block' }, schema['properties']['blocks']['items'])
    assert_equal({ 'Block' => 'SlackBlockKit.Block' }, b.type_mappings)
  end

  def test_type_overrides_are_applied_to_fields
    java(MODEL, 'Thing', '{ private String count; }')
    overrides = TypeOverrides.new({ "#{MODEL}.Thing#count" => { 'type' => 'integer', 'java_type' => 'String',
                                                                'reason' => 'r', 'evidence' => ['e'] } })
    b = builder(type_overrides: overrides)
    property = b.add_root('Thing', root(b, "#{MODEL}.Thing"))['properties']['count']

    assert_equal 'integer', property['type']
    assert_equal 'string', property['x-java-type']
    assert_empty overrides.unused_keys
  end

  def test_added_fields_are_merged
    java(MODEL, 'Thing', '{ private String a; }')
    overrides = TypeOverrides.new({ "#{MODEL}.Thing#extra" => { 'type' => 'schema', 'schema' => { 'type' => 'string' },
                                                                'added' => true, 'reason' => 'r', 'evidence' => ['e'] } })
    b = builder(type_overrides: overrides)
    props = b.add_root('Thing', root(b, "#{MODEL}.Thing"))['properties']

    assert_equal %w[a extra], props.keys
    assert_equal 'string', props['extra']['type']
  end

  def test_two_classes_cannot_claim_the_same_schema_name_or_one_class_two_names
    java(MODEL, 'One', '{ }')
    java(MODEL, 'Two', '{ }')
    b = builder
    b.add_root('X', root(b, "#{MODEL}.One"))

    assert_match(/used by both/, assert_raises(RuntimeError) { b.add_root('X', root(b, "#{MODEL}.Two")) }.message)
    assert_match(/emitted as both/, assert_raises(RuntimeError) { b.add_root('Y', root(b, "#{MODEL}.One")) }.message)
  end

  def test_map_to_swift_conflict_raises
    b = builder
    b.map_to_swift('Block', 'SlackBlockKit.Block', 'SlackBlockKit')

    assert_match(/mapped to both/, assert_raises(RuntimeError) { b.map_to_swift('Block', 'Other.Block', 'Other') }.message)
  end

  def test_handwritten_schema_via_adapter_and_x_java_class_expansion
    java('com.slack.api.model', 'Attachment', '{ public static class VideoHtml { private String ignored; } private VideoHtml videoHtml; }')
    java(MODEL, 'Source', '{ private String source; private Integer width; }')
    handwritten = {
      'AttachmentVideoHtml' => {
        'oneOf' => [{ 'type' => 'string' }, { 'x-java-class' => "#{MODEL}.Source" }, { '$ref' => '#/components/schemas/Other' }]
      },
      'Other' => { 'type' => 'object' },
      'Unused' => { 'type' => 'object' },
    }
    b = builder(handwritten: handwritten)
    schema = b.add_root('Attachment', root(b, 'com.slack.api.model.Attachment'))

    assert_equal({ '$ref' => '#/components/schemas/AttachmentVideoHtml' }, schema['properties']['video_html'])
    alternatives = b.components['AttachmentVideoHtml']['oneOf']
    assert_equal({ 'type' => 'string' }, alternatives[0])
    assert_equal({ '$ref' => '#/components/schemas/Source' }, alternatives[1])
    assert_equal %w[source width], b.components['Source']['properties'].keys
    assert_equal({ '$ref' => '#/components/schemas/Other' }, alternatives[2])
    assert_equal({ 'type' => 'object' }, b.components['Other'])
    assert_equal ['Unused'], b.unused_handwritten_schemas
  end

  def test_handwritten_ref_errors
    b = builder(handwritten: { 'Bad' => { 'x-java-class' => 'com.nowhere.Gone' } })

    assert_match(/has no schema Nope/, assert_raises(RuntimeError) { b.handwritten_ref('Nope') }.message)
    assert_match(/unknown x-java-class com\.nowhere\.Gone/, assert_raises(RuntimeError) { b.handwritten_ref('Bad') }.message)
  end

  def test_unsupported_adapter_type_raises
    java('com.slack.api.audit.response', 'LogsResponse', '{ private UserIDs ids; public static class UserIDs { } }')
    b = builder

    assert_match(/Gson adapter marked unsupported/,
                 assert_raises(RuntimeError) { b.add_root('LogsResponse', root(b, 'com.slack.api.audit.response.LogsResponse')) }.message)
  end
end
