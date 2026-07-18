# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/helpers'

class HelpersTest < Minitest::Test
  def test_generate_json_schema_writes_valid_output_atomically
    Dir.mktmpdir do |directory|
      quicktype = fake_quicktype(directory, <<~SH)
        printf '%s' '{"definitions":{"Example":{"type":"object"}}}'
      SH
      output = File.join(directory, 'schema.json')

      with_environment('QUICKTYPE_BIN' => quicktype) do
        parsed = generate_json_schema('input.json', output, 'Example')

        assert_equal 'object', parsed.dig('definitions', 'Example', 'type')
        assert_equal parsed, JSON.parse(File.read(output))
      end
    end
  end

  def test_generate_json_schema_rejects_invalid_output_without_writing_it
    Dir.mktmpdir do |directory|
      quicktype = fake_quicktype(directory, "printf '%s' 'not json'\n")
      output = File.join(directory, 'schema.json')

      error = with_environment('QUICKTYPE_BIN' => quicktype) do
        assert_raises(RuntimeError) do
          generate_json_schema('input.json', output, 'Example')
        end
      end

      assert_match(/invalid JSON/, error.message)
      refute_path_exists output
    end
  end

  def test_generation_concurrency_can_be_configured
    with_environment('GENERATION_JOBS' => '3') do
      assert_equal 3, generation_concurrency
    end

    with_environment('GENERATION_JOBS' => '0') do
      assert_raises(ArgumentError) { generation_concurrency }
    end
  end

  private

  def fake_quicktype(directory, body)
    path = File.join(directory, 'quicktype')
    File.write(path, "#!/bin/sh\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def with_environment(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
