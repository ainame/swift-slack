require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../generate_webapi'

class GenerateWebapiTest < Minitest::Test
  VENDOR_DIR = File.expand_path('../../vendor', __dir__)
  def test_only_supported_methods_with_java_fixtures_are_generated
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, 'schemas'))
      api_ref_paths = %w[
        usergroups/usergroups.list
        api/api.test
        rtm/rtm.connect
        admin/admin.apps.permissions.set
      ].map { File.join(VENDOR_DIR, "slack-api-ref/methods/#{_1}.json") }
      sample_paths = %w[usergroups.list api.test rtm.connect].map do
        File.join(VENDOR_DIR, "java-slack-sdk/json-logs/samples/api/#{_1}.json")
      end

      _, stderr = capture_io { main(api_ref_paths, sample_paths, directory) }
      schema = JSON.parse(File.read(File.join(directory, 'openapi.json')))

      # rtm.connect has a fixture but is a legacy API.
      assert_equal %w[api.test usergroups.list], schema.fetch('paths').keys.sort
      assert_match(/Skip admin\.apps\.permissions\.set: no java-slack-sdk fixture/, stderr)
    end
  end

  def test_operations_reference_the_schema_name_quicktype_emits
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, 'schemas'))
      api_ref_paths = [File.join(VENDOR_DIR, 'slack-api-ref/methods/api/api.test.json')]
      sample_paths = [File.join(VENDOR_DIR, 'java-slack-sdk/json-logs/samples/api/api.test.json')]

      capture_io { main(api_ref_paths, sample_paths, directory) }
      schema = JSON.parse(File.read(File.join(directory, 'openapi.json')))

      reference = schema.dig('paths', 'api.test', 'post', 'responses', '200', 'content', 'application/json', 'schema', '$ref')
      # quicktype emits APITestResponse, not the ApiTestResponse derived from the method name.
      assert_equal '#/components/schemas/APITestResponse', reference
      assert schema.fetch('components').fetch('schemas').key?('APITestResponse')
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
