#!/usr/bin/env ruby
# frozen_string_literal: true

# Collects the JSON payloads DecodeCheck runs against into inputs/ (git-ignored):
#   inputs/fixtures/<method>.json    java-slack-sdk response fixtures, minus the recorder's placeholder values (java_placeholders.rb)
#   inputs/docs/<method>.<n>.json    successful (`ok: true`) examples from slack-api-ref
#   inputs/live/<method>.json        real responses, only when LIVE_RESPONSES points at a directory of them
#   inputs/old-*/<method>.json       the same payloads laid out for OldHarness (swift-slack's current types)
#
# Usage: prepare_inputs.rb [method...]

require "json"
require "fileutils"
require_relative "java_placeholders"

HERE = __dir__
VENDOR = File.expand_path("../../vendor", HERE)
INPUTS = File.join(HERE, "inputs")
DOCUMENT = JSON.parse(File.read(File.join(HERE, "openapi.json"), encoding: "UTF-8"))
DEFAULT_METHODS = %w[team.info users.info conversations.list chat.postMessage admin.conversations.getConversationPrefs].freeze
METHODS = ARGV.empty? ? DEFAULT_METHODS : ARGV
INPUT_KINDS = %w[fixtures docs live old-fixtures old-docs1 old-docs2].freeze

FileUtils.rm_rf(Dir.glob(File.join(INPUTS, "*")))
INPUT_KINDS.each { |kind| FileUtils.mkdir_p(File.join(INPUTS, kind)) }

def read_json(path) = JSON.parse(File.read(path, encoding: "UTF-8"), **JavaPlaceholders::LENIENT)

def write_json(path, value) = File.write(path, JSON.generate(value))

METHODS.each do |method|
  fixture = File.join(VENDOR, "java-slack-sdk/json-logs/samples/api/#{method}.json")
  JavaPlaceholders.write_stripped_fixture(fixture, File.join(INPUTS, "fixtures/#{method}.json"), method, DOCUMENT)
  # The old harness skips payloads with ok=false, and the fixtures carry ok=false, so force ok=true.
  old_fixture = read_json(fixture).merge("ok" => true)
  write_json(File.join(INPUTS, "old-fixtures/#{method}.json"), old_fixture)

  doc = Dir.glob(File.join(VENDOR, "slack-api-ref/methods/*/#{method}.json")).min
  ok_examples = read_json(doc).dig("response", "examples").map { |example| JSON.parse(example, **JavaPlaceholders::LENIENT) }
                                                              .select { |example| example["ok"] == true }
  ok_examples.each.with_index(1) do |example, n|
    write_json(File.join(INPUTS, "docs/#{method}.#{n}.json"), example)
    write_json(File.join(INPUTS, "old-docs#{n}/#{method}.json"), example) if n <= 2
  end
end

live = ENV.fetch("LIVE_RESPONSES", "")
if live.empty?
  puts "LIVE_RESPONSES not set: skipping live inputs"
else
  METHODS.each do |method|
    path = File.join(live, "#{method}.json")
    FileUtils.cp(path, File.join(INPUTS, "live/#{method}.json")) if File.exist?(path)
  end
end
