# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../process_webapi'

class EventEnumTest < Minitest::Test
  EVENTS = {
    'MessageEvent' => { 'type' => 'message' },
    'MessageBotEvent' => { 'type' => 'message', 'subtype' => 'bot_message' },
    'IMCloseEvent' => { 'type' => 'im_close' },
  }.freeze

  def source
    @source ||= EventEnum.new(EVENTS).source
  end

  def test_case_names_are_lower_camel_without_event_suffix
    assert_includes source, 'case imClose(IMCloseEvent)'
    assert_includes source, 'case messageBot(MessageBotEvent)'
    assert_includes source, 'case message(MessageEvent)'
    assert_includes source, 'case unsupported(String)'
  end

  def test_acronym_words_in_case_names
    source = EventEnum.new({ 'ChannelIDChangedEvent' => { 'type' => 'channel_id_changed' } }).source

    assert_includes source, 'case channelIdChanged(ChannelIDChangedEvent)'
  end

  def test_plain_type_case
    assert_includes source, "        case \"im_close\":\n            self = try .imClose(IMCloseEvent(from: decoder))"
  end

  def test_message_type_switches_on_subtype
    assert_includes source, 'case "message":'
    assert_includes source, 'switch subtype {'
    assert_includes source, 'case "bot_message":'
    assert_includes source, 'self = try .messageBot(MessageBotEvent(from: decoder))'
    assert_includes source, "case nil:\n                self = try .message(MessageEvent(from: decoder))"
    assert_includes source, 'self = .unsupported("message - \(unknownSubtype)")'
  end

  def test_payload_switch_covers_every_case
    EVENTS.each_key do |name|
      case_name = name.delete_suffix('Event').gsub('ID', 'Id').gsub('IM', 'Im')
      assert_match(/case \.#{case_name[0].downcase}#{case_name[1..]}\(let event\):/, source)
    end
  end

  def test_subtype_only_events_fall_back_to_unsupported_for_missing_subtype
    source = EventEnum.new({ 'MessageBotEvent' => { 'type' => 'message', 'subtype' => 'bot_message' } }).source

    assert_includes source, "case nil:\n                self = .unsupported(type)"
  end

  def test_several_plain_events_with_same_type_raise
    events = { 'AEvent' => { 'type' => 'x' }, 'BEvent' => { 'type' => 'x' } }

    assert_raises(RuntimeError) { EventEnum.new(events).source }
  end

  def test_source_is_wrapped_in_events_trait
    assert source.start_with?("#if Events\nimport Foundation")
    assert source.end_with?("#endif\n")
  end
end

class APIGroupsTest < Minitest::Test
  GROUPS = %w[chat conversations lists dnd oauth].freeze

  def test_group_for_matches_prefix_of_operation_and_response_names
    assert_equal 'chat', APIGroups.group_for('chatPostMessage', groups: GROUPS)
    assert_equal 'chat', APIGroups.group_for('ChatPostMessage', groups: GROUPS)
    assert_equal 'conversations', APIGroups.group_for('ConversationsListResponse', groups: GROUPS)
    assert_equal 'dnd', APIGroups.group_for('DndInfoResponse', groups: GROUPS)
  end

  def test_slacklists_alias_maps_to_lists
    assert_equal 'lists', APIGroups.group_for('slackListsItemsCreate', groups: GROUPS)
    assert_equal 'lists', APIGroups.group_for('SlackListsCreateResponse', groups: GROUPS)
  end

  def test_unknown_name_raises
    error = assert_raises(UnknownAPIGroupError) { APIGroups.group_for('mysteryMethod', groups: GROUPS) }

    assert_match(/mysteryMethod/, error.message)
  end

  def test_trait_and_display_names
    assert_equal 'WebAPI_Chat', APIGroups.trait('chat')
    assert_equal 'WebAPI_DND', APIGroups.trait('dnd')
    assert_equal 'WebAPI_OAuth', APIGroups.trait('oauth')
    assert_equal 'OpenID', APIGroups.display_name('openid')
    assert_equal 'RTM', APIGroups.display_name('rtm')
  end

  def test_all_reads_group_names_from_a_directory
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'chat'))
      File.write(File.join(dir, 'chat', 'a.json'), '{"name":"chat.postMessage"}')
      File.write(File.join(dir, 'chat', 'b.json'), '{"name":"chat.update"}')
      File.write(File.join(dir, 'c.json'), '{"name":"pins.add"}')

      assert_equal %w[chat pins], APIGroups.all(dir).sort
    end
  end

  def test_all_raises_when_directory_has_no_groups
    Dir.mktmpdir do |dir|
      assert_raises(RuntimeError) { APIGroups.all(dir) }
    end
  end
end
