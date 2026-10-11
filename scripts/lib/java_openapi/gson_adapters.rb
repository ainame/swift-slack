# frozen_string_literal: true

# Types that upstream java-slack-sdk deserializes through a registered Gson type adapter instead of the
# class declaration (GsonFactory.registerTypeAdapters). Their JSON shape is decided by adapter code, so the
# class cannot be translated field by field. Every registered adapter needs an explicit decision here;
# `GsonAdapters.validate!` fails when GsonFactory registers a type without one, or when an entry is stale.
module GsonAdapters
  GSON_FACTORY = 'slack-api-client/src/main/java/com/slack/api/util/json/GsonFactory.java'

  # A decision for one adapter type.
  #                   typeOverrides; `module` says which downstream swift-slack module defines it
  #   :untyped      - emit `{}` (any JSON value)
  #   :declared     - translate the class declaration anyway, because the adapter only drops malformed values
  #   :unsupported  - must not be reachable from a generated schema; generation fails if it is
  Decision = Struct.new(:kind, :swift, :module, :schema, :reason, keyword_init: true)

  DECISIONS = {
    'java.time.Instant' => Decision.new(
      kind: :unsupported, reason: 'Only RTM pong events use it, which are not generated.'
    ),
    'com.slack.api.model.File' => Decision.new(
      kind: :declared,
      reason: 'The adapter only removes non-array favorites/channels/ims/groups values and normalizes shares.'
    ),
    'com.slack.api.model.block.LayoutBlock' => Decision.new(
      kind: :swift, swift: 'SlackBlockKit.Block', module: 'SlackBlockKit', reason: 'Block Kit blocks.'
    ),
    'com.slack.api.model.block.composition.TextObject' => Decision.new(
      kind: :swift, swift: 'SlackBlockKit.TextObject', module: 'SlackBlockKit', reason: 'Block Kit text objects.'
    ),
    'com.slack.api.model.block.ContextBlockElement' => Decision.new(
      kind: :untyped, reason: 'Only used inside Block Kit blocks, which SlackBlockKit decodes.'
    ),
    'com.slack.api.model.block.ContextActionsBlockElement' => Decision.new(
      kind: :untyped, reason: 'Only used inside Block Kit blocks, which SlackBlockKit decodes.'
    ),
    'com.slack.api.model.block.element.BlockElement' => Decision.new(
      kind: :untyped, reason: 'Only used inside Block Kit blocks, which SlackBlockKit decodes.'
    ),
    'com.slack.api.model.block.element.RichTextElement' => Decision.new(
      kind: :untyped, reason: 'Only used inside Block Kit blocks, which SlackBlockKit decodes.'
    ),
    'com.slack.api.model.event.FunctionExecutedEvent.InputValue' => Decision.new(
      kind: :unsupported, reason: 'function_executed has no upstream fixture and is not generated.'
    ),
    'com.slack.api.model.Attachment.VideoHtml' => Decision.new(
      kind: :schema, schema: 'AttachmentVideoHtml',
      reason: 'A string of HTML or an object with `source`.'
    ),
    'com.slack.api.model.event.MessageChangedEvent.PreviousMessage' => Decision.new(
      kind: :schema, schema: 'MessageChangedEventPreviousMessage',
      reason: 'A message object, or an empty array when there is none.'
    ),
    'com.slack.api.model.admin.AppWorkflow.StepInputValue' => Decision.new(
      kind: :schema, schema: 'AppWorkflowStepInputValue',
      reason: 'A string, an array of strings, an array of blocks, or an object with `elements` and `required`.'
    ),
    'com.slack.api.model.admin.AppWorkflow.StepInputValueElementDefault' => Decision.new(
      kind: :schema, schema: 'AppWorkflowStepInputValueElementDefault',
      reason: 'A string or an array of strings.'
    ),
    'com.slack.api.audit.response.LogsResponse.DetailsChangedValue' => Decision.new(
      kind: :unsupported, reason: 'The Audit Logs API is not part of the generated Web API.'
    ),
    'com.slack.api.audit.response.LogsResponse.UserIDs' => Decision.new(
      kind: :unsupported, reason: 'The Audit Logs API is not part of the generated Web API.'
    ),
    'com.slack.api.model.list.ListView.Grouping' => Decision.new(
      kind: :schema, schema: 'ListViewGrouping',
      reason: 'An object whose `order` may be an array or an empty string.'
    ),
  }.freeze

  module_function

  def decision_for(fqn)
    DECISIONS[fqn]
  end

  # Fully qualified names of the types GsonFactory.java registers adapters for.
  def registered_types(sdk_dir)
    source = File.read(File.join(sdk_dir, GSON_FACTORY), encoding: 'UTF-8')
    imports = source.scan(/^import\s+([\w.]+);/).flatten
    source.scan(/registerTypeAdapter\(\s*([\w.]+)\.class/).flatten.map do |name|
      first = name.split('.').first
      import = imports.find { |candidate| candidate.end_with?(".#{first}") } or
        raise "#{GSON_FACTORY}: cannot resolve adapter type `#{name}`"
      "#{import.delete_suffix(".#{first}")}.#{name}"
    end
  end

  # Fails unless DECISIONS covers exactly the types GsonFactory registers.
  def validate!(sdk_dir)
    registered = registered_types(sdk_dir)
    missing = registered - DECISIONS.keys
    stale = DECISIONS.keys - registered
    raise "Gson adapter types without a decision in #{__FILE__}: #{missing.join(', ')}" unless missing.empty?
    raise "Gson adapter decisions for types no longer registered: #{stale.join(', ')}" unless stale.empty?
  end
end
