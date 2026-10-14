# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'java_test_support'
require_relative '../lib/java_openapi'
require_relative '../lib/slack_code_schemas'

class SlackCodeSchemasTest < Minitest::Test
  include JavaTestSupport

  def setup
    write_java('Example.java', 'package example; public class Example { private String existing; }')
  end

  def supplement(properties = { 'missing' => { 'type' => 'string' } })
    SlackCodeSchemas.new('example.Example' => {
      'source' => 'https://docs.slack.dev/ai/slack-code/', 'properties' => properties,
    })
  end

  def test_upstream_adoption_requires_removing_the_exception
    error = assert_raises(RuntimeError) { supplement('existing' => { 'type' => 'string' }).validate!(build_index) }
    assert_match(/java-slack-sdk now declares example.Example: existing/, error.message)
  end

  def test_upstream_event_adoption_requires_its_own_fixture
    write_java('CodeChannelActionEvent.java', <<~JAVA)
      package com.slack.api.model.event;
      public class CodeChannelActionEvent { public static final String TYPE_NAME = "code_channel_action"; }
    JAVA
    error = assert_raises(RuntimeError) { supplement.validate!(build_index) }
    assert_match(/now models code_channel_action/, error.message)
  end

  def test_missing_owner_fails_instead_of_silently_dropping_fields
    entries = { 'example.Removed' => { 'source' => 'https://docs.slack.dev/', 'properties' => {} } }
    error = assert_raises(RuntimeError) { SlackCodeSchemas.new(entries).validate!(build_index) }
    assert_match(/unknown Java class example.Removed/, error.message)
  end

  def test_unreferenced_exception_fails_full_generation
    supplement = supplement()
    supplement.validate!(build_index)
    assert_raises(RuntimeError) { supplement.check_used! }
    added = supplement.additions_for(build_index.fully_qualified('example.Example'))
    assert_match(/Downstream swift-slack.*upstream java-slack-sdk.*https:/, added.fetch('missing').fetch('description'))
    supplement.check_used!
  end

  def test_opaque_event_does_not_invent_a_payload_contract
    schema = supplement.event_schema
    assert_equal ['type'], schema.fetch('properties').keys
    assert_equal ['type'], schema.fetch('required')
    assert_equal true, schema.fetch('additionalProperties')
  end
end
