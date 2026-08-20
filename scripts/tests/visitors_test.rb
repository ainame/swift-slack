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
