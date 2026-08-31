#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'process_webapi'

class ProcessWebAPITest < Minitest::Test
  def test_catalog_discovers_new_group_and_resolves_generated_names
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'agents.json'), JSON.generate({ 'name' => 'agents' }))

      groups = APIGroupCatalog.load(directory)

      assert_includes groups, 'agents'
      assert_equal 'agents', APIGroupResolver.group_for('AgentsSessionsRename', groups: groups)
    end
  end

  def test_unknown_group_aborts_processing
    error = assert_raises(UnknownAPIGroupError) do
      APIGroupResolver.group_for('FutureFeatureCreate', groups: ['agents'])
    end

    assert_equal 'Unable to determine Slack API group for FutureFeatureCreate', error.message
  end

  def test_schema_groups_are_canonical_before_trait_formatting
    group = SchemaGroupDeterminer.determine_schema_group('OauthV2ExchangeResponse')

    assert_equal 'oauth', group
    assert_equal 'OAuth', GroupNameFormatter.capitalize_group_name(group)
  end

  def test_component_splitter_uses_the_oauth_trait
    content = <<~SWIFT
      /// Types generated from the components section of the OpenAPI document.
      public enum Components {
          public enum Schemas {
              /// - Remark: Generated from `#/components/schemas/OauthV2ExchangeResponse`.
              public struct OauthV2ExchangeResponse: Codable {
              }
          }
      }
    SWIFT

    result = ComponentsSplitter.new('/tmp').send(:parse_components_by_schemas, content)

    assert_equal ['oauth'], result[:groups].keys
    assert_includes result[:groups]['oauth'], '#if WebAPI_OAuth'
  end
end
