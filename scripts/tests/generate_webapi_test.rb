require 'minitest/autorun'
require 'tmpdir'
require_relative '../generate_webapi'

class GenerateWebapiTest < Minitest::Test
  def test_reference_only_permissions_methods_keep_operations_and_response_fields
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, 'schemas'))
      paths = REFERENCE_RESPONSE_METHODS.map do |name|
        File.expand_path("../../vendor/slack-api-ref/methods/admin/#{name}.json", __dir__)
      end
      main(paths, [], directory)
      schema = JSON.parse(File.read(File.join(directory, 'openapi.json')))

      REFERENCE_RESPONSE_METHODS.each do |name|
        operation = schema.fetch('paths').fetch(name).fetch('post')
        assert operation.dig('requestBody', 'content', 'application/json', 'schema', 'properties').key?('channel_ids')
        reference = operation.dig('responses', '200', 'content', 'application/json', 'schema', '$ref')
        properties = schema.fetch('components').fetch('schemas').fetch(reference.split('/').last).fetch('properties')
        assert_equal 'boolean', properties.dig('ok', 'type')
        assert_equal 'string', properties.dig('permission_type', 'type')
        assert_equal 'string', properties.dig('channel_restriction_mode', 'type')
        assert_equal 'string', properties.dig('channel_ids', 'items', 'type')
      end
    end
  end

  def test_empty_examples_keep_minimal_success_fallback
    assert_equal [{ 'ok' => true }], reference_response_samples('entity.example', { 'response' => { 'examples' => [] } })
  end

  def test_multiple_examples_infer_one_response_object
    Dir.mktmpdir do |directory|
      paths = [{ 'ok' => true, 'channel_ids' => ['C123'] }, { 'ok' => false, 'error' => 'invalid_auth' }].each_with_index.map do |sample, index|
        path = File.join(directory, "sample#{index}.json")
        File.write(path, JSON.generate(sample))
        path
      end
      schema = generate_json_schema(paths, File.join(directory, 'schema.json'), 'ExampleResponse')
      properties = schema.fetch('definitions').fetch('ExampleResponse').fetch('properties')
      assert_equal 'string', properties.dig('error', 'type')
      assert_equal 'string', properties.dig('channel_ids', 'items', 'type')
    end
  end

  def test_unreviewed_reference_only_methods_remain_unsupported
    assert_nil reference_response_samples('unknown.method', { 'response' => { 'examples' => ['{}'] } })
  end

  def test_invalid_reviewed_examples_fail
    assert_raises(JSON::ParserError) do
      reference_response_samples(REFERENCE_RESPONSE_METHODS.first, { 'response' => { 'examples' => ['invalid'] } })
    end
  end
end
