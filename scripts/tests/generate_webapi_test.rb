require 'minitest/autorun'
require 'stringio'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../generate_webapi'

class GenerateWebapiTest < Minitest::Test
  VENDOR_DIR = File.expand_path('../../vendor', __dir__)

  def build(methods, events: [])
    api_ref_paths = methods.map { |method| Dir.glob(File.join(VENDOR_DIR, "slack-api-ref/methods/*/#{method}.json")).first }
    event_paths = events.map { |event| File.join(VENDOR_DIR, "java-slack-sdk/json-logs/samples/events/#{event}Payload.json") }
    openapi = nil
    _, stderr = capture_io { openapi, = build_openapi(api_ref_paths, methods.to_set - ['admin.apps.permissions.set'], event_paths) }
    [openapi, stderr]
  end

  def test_only_supported_methods_with_java_fixtures_are_generated
    openapi, stderr = build(%w[usergroups.list api.test rtm.connect admin.apps.permissions.set])

    # rtm.connect has a fixture but is a legacy API.
    assert_equal %w[api.test usergroups.list], openapi.fetch('paths').keys.sort
    assert_match(/Skip admin\.apps\.permissions\.set: no java-slack-sdk fixture/, stderr)
  end

  def test_responses_come_from_java_response_classes
    openapi, = build(%w[api.test oauth.v2.access])
    schemas = openapi.dig('components', 'schemas')

    reference = openapi.dig('paths', 'api.test', 'post', 'responses', '200', 'content', 'application/json', 'schema', '$ref')
    assert_equal '#/components/schemas/APITestResponse', reference
    assert_equal %w[ok], schemas.dig('APITestResponse', 'required')
    assert_equal 'object', schemas.dig('APITestResponse', 'properties', 'args', 'type')
    assert schemas.key?('OauthV2AccessResponse'), 'oauth.v2.access uses OAuthV2AccessResponse in java-slack-sdk'
  end

  def test_top_level_model_classes_are_shared_schemas
    openapi, = build(%w[users.info conversations.info])
    schemas = openapi.dig('components', 'schemas')

    assert_equal '#/components/schemas/User', schemas.dig('UsersInfoResponse', 'properties', 'user', '$ref')
    assert_equal '#/components/schemas/Conversation', schemas.dig('ConversationsInfoResponse', 'properties', 'channel', '$ref')
    assert schemas.dig('User', 'properties', 'profile', 'properties'), 'User.Profile is an inline schema'
    assert_nil schemas.dig('User', 'required')
  end

  def test_events_are_marked_with_their_type_and_subtype
    openapi, = build([], events: %w[ImClose MessageBot])

    assert_equal({ 'IMCloseEvent' => { 'type' => 'im_close' },
                   'MessageBotEvent' => { 'type' => 'message', 'subtype' => 'bot_message' } },
                 openapi['x-slack-events'])
    assert_equal %w[type], openapi.dig('components', 'schemas', 'IMCloseEvent', 'required')
  end

  def test_block_kit_and_type_overrides
    openapi, builder = nil
    capture_io do
      openapi, builder = build_openapi([Dir.glob(File.join(VENDOR_DIR, 'slack-api-ref/methods/*/files.info.json')).first],
                                       Set['files.info'], [])
    end
    file = openapi.dig('components', 'schemas', 'File', 'properties')

    assert_equal 'SlackBlockKit.Block', builder.type_mappings['Block']
    assert_equal 'integer', file.dig('original_w', 'type')
    assert_equal 'string', file.dig('original_w', 'x-java-type')
    assert_match(/declared `String`, but recorded responses send integers/, file.dig('original_w', 'description'))
  end

  def test_reads_utf8_sources_under_a_non_utf8_locale
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'api.test.json')
      File.write(path, JSON.generate('desc' => 'Checks the API’s availability', 'args' => {}))
      script = <<~RUBY
        require #{File.expand_path('../generate_webapi', __dir__).dump}
        print generate_openapi_path(ARGV[0], 'APITestResponse').dig(:'api.test', :post, :summary)
      RUBY

      stdout, stderr, status = Open3.capture3(
        { 'LANG' => 'C', 'LC_ALL' => 'C' }, RbConfig.ruby, '-e', script, path,
      )

      assert status.success?, stderr
      assert_equal 'Checks the API’s availability', stdout.force_encoding(Encoding::UTF_8)
    end
  end

  def test_warnings_are_reported_once_on_github_actions
    Dir.mktmpdir do |directory|
      summary_path = File.join(directory, 'summary.md')
      io = StringIO.new
      warnings = ['Skip a.b: 100% missing', 'Skip c.d: no data']
      report_generator_warnings(warnings, env: { 'GITHUB_ACTIONS' => 'true', 'GITHUB_STEP_SUMMARY' => summary_path }, io: io)

      assert_equal "::warning title=Web API generation: 2 warning(s)::Skip a.b: 100%25 missing%0ASkip c.d: no data\n", io.string
      summary = File.read(summary_path)
      assert_includes summary, '- Skip a.b: 100% missing'
      assert_includes summary, '- Skip c.d: no data'
    end
  end

  def test_warnings_are_not_annotated_outside_github_actions
    io = StringIO.new
    report_generator_warnings(['Skip c.d: no data'], env: {}, io: io)
    assert_empty io.string
  end

  def test_legacy_methods_are_unsupported_by_prefix
    %w[channels.list groups.list im.open mpim.open rtm.connect dialog.open files.comments.delete oauth.access].each do |name|
      assert unsupported_method?(name), "#{name} should be unsupported"
    end
    %w[usergroups.list admin.usergroups.addTeams admin.workflows.search functions.workflows.steps.list oauth.v2.access].each do |name|
      refute unsupported_method?(name), "#{name} should be supported"
    end
  end
end
