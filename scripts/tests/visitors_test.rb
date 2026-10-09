# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/visitors'

class VisitorsTest < Minitest::Test
  def test_acronyms_fixer_normalizes_mcp_component_names_and_references
    schema = JSON.parse(<<~JSON)
      {
        "$ref": "#/definitions/AdminAppsMCPServersListResponse",
        "definitions": {
          "AdminAppsMCPServersListResponse": { "type": "object" }
        }
      }
    JSON

    AcronymsFixer.new('MCP' => 'Mcp').walk(schema)

    assert_equal '#/definitions/AdminAppsMcpServersListResponse', schema['$ref']
    assert_equal({ 'type' => 'object' }, schema.dig('definitions', 'AdminAppsMcpServersListResponse'))
    refute schema['definitions'].key?('AdminAppsMCPServersListResponse')
  end
end

class ConversationPropertiesRefFixerTest < Minitest::Test
  def test_keeps_all_conversation_fields_when_later_fixtures_are_merged
    require 'tmpdir'
    require_relative '../generate_webapi'
    definitions_by_fixture = Dir.mktmpdir do |directory|
      %w[admin.conversations.search conversations.info conversations.join conversations.list users.conversations].to_h do |method|
        path = File.expand_path("../../vendor/java-slack-sdk/json-logs/samples/api/#{method}.json", __dir__)
        generated = generate_openapi_component(path, directory)
        [method, JSON.parse(File.read(generated))['definitions']]
      end
    end
    schemas = definitions_by_fixture.values
    refute_empty schemas
    merged = SchemaMerge.merge_all(definitions_by_fixture, policies: MERGE_POLICIES)
    ConversationPropertiesRefFixer::FIELDS.each do |field, model|
      assert_equal "#/components/schemas/#{model}", merged.dig('Properties', 'properties', field, '$ref')
      assert_equal 'object', merged.dig(model, 'type')
      assert_empty merged.dig(model, 'properties')
    end
    expected_fields = schemas.flat_map { _1.dig('Properties', 'properties').keys }.uniq.sort
    assert_equal expected_fields, merged.dig('Properties', 'properties').keys.sort
    %w[at_here_restricted at_channel_restricted].each do |field|
      assert_equal 'boolean', merged.dig('Properties', 'properties', field, 'type')
    end
    assert_equal 'array', merged.dig('Properties', 'properties', 'channel_workflows', 'type')
    assert_equal 'string', merged.dig('Properties', 'properties', 'use_case', 'type')
  end

  def test_does_not_invent_fields_absent_from_a_conversation_fixture
    schema = { 'definitions' => { 'Properties' => { 'type' => 'object', 'properties' => { 'use_case' => { 'type' => 'string' } } } } }
    original = Marshal.load(Marshal.dump(schema))
    ConversationPropertiesRefFixer.new.walk(schema)
    assert_equal original, schema
  end

  def test_does_not_add_conversation_fields_to_unrelated_schemas
    schema = { 'definitions' => { 'Other' => { 'type' => 'object' } } }
    original = Marshal.load(Marshal.dump(schema))
    ConversationPropertiesRefFixer.new.walk(schema)
    assert_equal original, schema
  end
end
