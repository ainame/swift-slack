# frozen_string_literal: true

require 'minitest/autorun'
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
  def test_keeps_new_fields_when_later_fixtures_replace_properties
    require 'tmpdir'
    require_relative '../generate_webapi'
    schemas = Dir.mktmpdir do |directory|
      %w[conversations.info conversations.join conversations.list users.conversations].map do |method|
        path = "vendor/java-slack-sdk/json-logs/samples/api/#{method}.json"
        generated = generate_openapi_component(path, directory)
        JSON.parse(File.read(generated))['definitions']
      end
    end
    refute_empty schemas
    merged = schemas.reduce({}, &:merge)
    ConversationPropertiesRefFixer::FIELDS.each do |field, model|
      assert_equal "#/components/schemas/#{model}", merged.dig('Properties', 'properties', field, '$ref')
      assert_equal 'object', merged.dig(model, 'type')
      assert_empty merged.dig(model, 'properties')
    end
    assert_equal 'string', merged.dig('Properties', 'properties', 'use_case', 'type')
  end

  def test_does_not_add_conversation_fields_to_unrelated_schemas
    schema = { 'definitions' => { 'Other' => { 'type' => 'object' } } }
    original = Marshal.load(Marshal.dump(schema))
    ConversationPropertiesRefFixer.new.walk(schema)
    assert_equal original, schema
  end
end
