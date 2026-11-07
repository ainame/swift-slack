# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/event_fixtures'

class EventFixturesTest < Minitest::Test
  JAVA_TEST = <<~'JAVA'
    public class FooEventTest {
        @Test
        public void deserialize() {
            String json = "{\n" +
                    "    \"type\": \"foo\",\n" +
                    "    \"names\": [\"a\\\"b\"]\n" +
                    "}";
        }

        @Test
        public void serialize() {
            String expectedJson = "{\"type\":\"other\"}";
        }
    }
  JAVA

  def setup
    @dir = Dir.mktmpdir
    @sdk_dir = File.join(@dir, 'sdk')
    @local_dir = File.join(@dir, 'event_fixtures')
    @manifest_path = File.join(@dir, 'event_fixtures.yml')
    write('sdk/json-logs/samples/events/BarPayload.json', '{}')
    write('sdk/FooEventTest.java', JAVA_TEST)
    write('event_fixtures/FooPayload.json', '{"type": "foo", "names": ["a\"b"]}')
    write('event_fixtures.yml', "Foo:\n  java_test: FooEventTest.java\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(path, content)
    path = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def paths
    EventFixtures.paths(sdk_dir: @sdk_dir, manifest_path: @manifest_path, local_dir: @local_dir).map { File.basename(_1) }
  end

  def assert_invalid(pattern)
    error = assert_raises(RuntimeError) { paths }
    assert_match pattern, error.message
  end

  def test_upstream_and_downstream_fixtures_are_combined
    assert_equal %w[BarPayload.json FooPayload.json], paths
  end

  def test_java_json_payloads_reads_string_json_declarations
    assert_equal [{ 'type' => 'foo', 'names' => ['a"b'] }], EventFixtures.java_json_payloads(JAVA_TEST)
  end

  def test_payload_must_equal_the_unit_test_json
    write('event_fixtures/FooPayload.json', '{"type": "other"}')
    assert_invalid(/FooPayload\.json differs from every `String json` payload in .*FooEventTest\.java/)
  end

  def test_unit_test_must_exist
    write('event_fixtures.yml', "Foo:\n  java_test: Missing.java\n")
    assert_invalid(/upstream unit test .*Missing\.java does not exist/)
  end

  def test_entries_and_payloads_must_pair_up
    write('event_fixtures/BazPayload.json', '{}')
    assert_invalid(/payloads without an event_fixtures\.yml entry: Baz/)

    File.delete(File.join(@local_dir, 'BazPayload.json'))
    write('event_fixtures.yml', "Foo:\n  java_test: FooEventTest.java\nQux:\n  java_test: FooEventTest.java\n")
    assert_invalid(/lists Qux, but .*QuxPayload\.json is missing/)
  end

  def test_upstream_recording_retires_the_downstream_payload
    write('sdk/json-logs/samples/events/FooPayload.json', '{}')
    assert_invalid(/now records FooPayload\.json: delete .*FooPayload\.json and its event_fixtures\.yml entry/)
  end

  def test_repository_payloads_match_their_upstream_unit_tests
    assert_equal %w[AgentSessionStopped AgentSessionTitleChanged],
                 EventFixtures.local_paths.map { File.basename(_1, '.json').delete_suffix('Payload') }
  end
end
