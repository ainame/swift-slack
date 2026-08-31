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
end
