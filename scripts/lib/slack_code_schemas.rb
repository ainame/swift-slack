# frozen_string_literal: true

require 'yaml'
require 'set'

# Narrow downstream swift-slack supplements to the upstream java-slack-sdk declarations.
# See scripts/slack_code_schemas.yml for Slack's official schema sources. These are
# documented contracts, not recorded upstream responses; regression payloads stay separate.
class SlackCodeSchemas
  ROOT = File.expand_path('../..', __dir__)
  PATH = File.join(ROOT, 'scripts/slack_code_schemas.yml')
  EVENT_NAME = 'CodeChannelActionEvent'
  EVENT_TYPE = 'code_channel_action'
  EVENT_FIXTURE = File.join(ROOT, 'scripts/slack_code_fixtures/CodeChannelActionPayload.json')

  def self.load
    new(YAML.safe_load_file(PATH))
  end

  def initialize(entries)
    @entries = entries
    @used = Set.new
  end

  # Fail when upstream supplies a field or event so its model/fixtures take over.
  def validate!(index)
    @entries.each do |fqn, entry|
      java_class = index.fully_qualified(fqn) or raise "Slack Code supplement: unknown Java class #{fqn}"
      raise "Slack Code supplement #{fqn} has no official source" unless entry.fetch('source').start_with?('https://docs.slack.dev/')

      overlap = entry.fetch('properties').keys & index.fields_of(java_class).keys
      raise "java-slack-sdk now declares #{fqn}: #{overlap.join(', ')}; remove the Slack Code supplement" unless overlap.empty?
    end
    event = index.package_classes(JavaOpenAPI::EVENT_PACKAGE).values.find do |java_class|
      java_class.constants['TYPE_NAME'] == EVENT_TYPE || java_class.name == EVENT_NAME
    end
    raise "java-slack-sdk now models #{EVENT_TYPE}; use its event and fixture" if event
  end

  def additions_for(java_class)
    entry = @entries[java_class.fqn]
    return {} unless entry

    @used << java_class.fqn
    entry.fetch('properties').transform_values do |schema|
      schema.merge('description' => "Downstream swift-slack Slack Code supplement; not yet declared by upstream java-slack-sdk. Source: #{entry.fetch('source')}")
    end
  end

  def check_used!
    unused = @entries.keys - @used.to_a
    raise "unused Slack Code supplements: #{unused.join(', ')}" unless unused.empty?
  end

  # Slack documents the event's existence but does not publish a payload schema.
  # Preserve every field instead of guessing names/types from other SDKs or apps.
  def event_schema
    {
      'type' => 'object',
      'description' => 'A Slack Code context-bar action. Slack documents this event at https://docs.slack.dev/ai/slack-code/code-channel-properties/ but publishes no payload schema. Downstream swift-slack preserves all fields in additionalProperties without assuming their shape. The regression fixture is synthetic, not a recorded Slack payload.',
      'properties' => { 'type' => { 'type' => 'string' } },
      'required' => ['type'],
      'additionalProperties' => true,
    }
  end
end
