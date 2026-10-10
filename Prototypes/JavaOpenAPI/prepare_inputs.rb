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

HERE = File.expand_path(__dir__)
VENDOR = File.expand_path("../../vendor", HERE)
INPUTS = File.join(HERE, "inputs")
DOCUMENT = JSON.parse(File.read(File.join(HERE, "openapi.json"), encoding: "UTF-8"))
METHODS = ARGV.empty? ? %w[team.info users.info conversations.list chat.postMessage
                           admin.conversations.getConversationPrefs] : ARGV

FileUtils.rm_rf(Dir.glob(File.join(INPUTS, "*")))
%w[fixtures docs live old-fixtures old-docs1 old-docs2].each { |d| FileUtils.mkdir_p(File.join(INPUTS, d)) }

def write_json(path, value)
  File.write(path, JSON.generate(value))
end

METHODS.each do |method|
  fixture = File.join(VENDOR, "java-slack-sdk/json-logs/samples/api/#{method}.json")
  JavaPlaceholders.write_stripped_fixture(fixture, File.join(INPUTS, "fixtures/#{method}.json"), method, DOCUMENT)
  # The old harness skips payloads with ok=false, and the fixtures carry ok=false, so force ok=true.
  old_fixture = JSON.parse(File.read(fixture, encoding: "UTF-8"), allow_duplicate_key: true).merge("ok" => true)
  write_json(File.join(INPUTS, "old-fixtures/#{method}.json"), old_fixture)

  doc = Dir.glob(File.join(VENDOR, "slack-api-ref/methods/*/#{method}.json")).min
  examples = JSON.parse(File.read(doc, encoding: "UTF-8"), allow_duplicate_key: true).dig("response", "examples")
  ok_examples = examples.map { |e| JSON.parse(e, allow_duplicate_key: true) }.select { |j| j["ok"] == true }
  ok_examples.each_with_index do |example, i|
    write_json(File.join(INPUTS, "docs/#{method}.#{i + 1}.json"), example)
    write_json(File.join(INPUTS, "old-docs#{i + 1}/#{method}.json"), example) if i < 2
  end
end

if (live = ENV["LIVE_RESPONSES"]) && !live.empty?
  METHODS.each do |method|
    path = File.join(live, "#{method}.json")
    FileUtils.cp(path, File.join(INPUTS, "live/#{method}.json")) if File.exist?(path)
  end
else
  puts "LIVE_RESPONSES not set: skipping live inputs"
end
