#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'process_webapi'

class ProcessWebAPITest < Minitest::Test
  def test_handwritten_alias_is_used_by_response_references
    Dir.mktmpdir do |directory|
      handwritten = File.join(directory, 'SlackModels')
      FileUtils.mkdir_p(handwritten)
      File.write(File.join(handwritten, 'TabData.swift'), 'public struct TabData {}')
      types = File.join(directory, 'Types.swift')
      File.write(types, <<~SWIFT)
        public enum Components {
            public enum Schemas {
                /// - Remark: Generated from `#/components/schemas/Data`.
                public struct Data: Codable {
                }
            }
        }
      SWIFT
      output = File.join(directory, 'Generated')
      capture_io { SlackModelsExtractor.new(types, output, handwritten_models_dir: handwritten).extract }
      assert_empty Dir.glob(File.join(output, '*.swift'))

      response = "public var data: Components.Schemas.Data?\n"
      with_slackmodels_types(SlackModelCatalog.handwritten_types(handwritten)) do
        transformed = CodeTransformer.transform_components_content(response)
        assert_includes transformed, 'public var data: SlackModels.TabData?'
        assert_includes transformed, 'import SlackModels'
        refute_includes transformed, 'Components.Schemas.Data'
      end
    end
  end

  def test_aliased_operation_reference_adds_slackmodels_import
    with_slackmodels_types(['TabData']) do
      result = CodeTransformer.transform_operations_content("public var data: Components.Schemas.Data?\n")
      assert_includes result, 'public var data: SlackModels.TabData?'
      assert_includes result, 'import SlackModels'
    end
  end

  def test_aliased_client_reference_adds_slackmodels_import
    with_slackmodels_types(['TabData']) do
      processor = CodeGenerationProcessor.new('/unused', '/unused/Generated')
      result = processor.send(:generate_extension_content, 'api',
                              ["func sample(_ data: Components.Schemas.Data) {}\n"], ["import Foundation\n"])
      assert_includes result, 'func sample(_ data: SlackModels.TabData)'
      assert_includes result, 'import SlackModels'
    end
  end

  def test_unknown_schema_references_are_not_redirected_to_slackmodels
    with_slackmodels_types(['TabData']) do
      reference = "public var other: Components.Schemas.Other?\n"
      assert_equal reference, CodeTransformer.transform_components_content(reference)
      assert_equal reference, CodeTransformer.transform_operations_content(reference)
      assert_equal reference, CodeTransformer.transform_client_functions(reference)
    end
  end

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
  private

  def with_slackmodels_types(types)
    previous = CodeTransformer.instance_variable_get(:@slackmodels_types)
    CodeTransformer.instance_variable_set(:@slackmodels_types, types)
    yield
  ensure
    CodeTransformer.instance_variable_set(:@slackmodels_types, previous)
  end

end
