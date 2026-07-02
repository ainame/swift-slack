#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require_relative './lib/helpers'
require_relative './lib/visitors'

# Deprecated events are skipped
UNSUPPORTED_EVENTS = [
  /^Resources/,
  /^UserResource/,
  /^FileCommentAdded$/,
  /^FileCommentEdited$/,
].freeze

tmp_dir = '.tmp'
source_dir = "vendor/java-slack-sdk/json-logs/samples/events"
events_dir = "#{tmp_dir}/Events/intermediates"
event_schemas_dir = "#{tmp_dir}/Events/schemas"

FileUtils.mkdir_p(events_dir)
FileUtils.mkdir_p(event_schemas_dir)

# Before generating JSON schema with quicktype. We need to normalize payload jsons.
# Some JSONs contain entire payload, others contain only event itself.
# Extract event if nested.
events = Dir.glob("#{source_dir}/*.json").sort
events.each do |path|
  model_name = File.basename(path, '.json').sub('Payload', 'Event')
  if UNSUPPORTED_EVENTS.any? { _1 =~ model_name }
    "Skip #{model_name} unsupported"
    next
  end

  output_path = File.join(events_dir, "#{model_name}.json")
  json = JSON.parse(File.read(path))
  normalized_json = if json.key?('token') && json.key?('event')
                      puts "Normalized #{path}"
                      json['event']
                    else
                      json
                    end
  File.write(output_path, JSON.pretty_generate(normalized_json))
end

# Generate JSON schemas with quicktype
normalized_events = Dir.glob("#{events_dir}/*.json").sort
process_in_queue(normalized_events) do |path|
  model_name = File.basename(path, '.json')
  output_path = File.join(event_schemas_dir, "#{model_name}.json")
  if File.exist?(output_path)
    puts "Skip #{model_name} - #{output_path} exists already"
    next
  end

  command = 'npx quicktype --lang schema' \
            ' --alphabetize-properties' \
            ' --all-properties-optional' \
            " --top-level #{model_name}" \
            " #{path}" \
            " > #{output_path}"
  puts "Generating schema: $ #{command}"
  system(command)
end

# Update JSON schemas
visitors = [
  InvalidKeysRemover.new,
  ReferenceFixer.new,
  AcronymsFixer.new('DND' => 'Dnd'),
  TypeFixer.new,
  UserProfileRefFixer.new,
  TeamProfileRefFixer.new,
  OptionalityFixer.new,
]

event_schemas = Dir.glob("#{event_schemas_dir}/*.json").sort
event_schemas.each do |path|
  json = JSON.parse(File.read(path))
  visitors.each { _1.walk(json) }
  File.write(path, JSON.pretty_generate(json))
end

# Merge JSON schemas
openapi = JSON.parse(File.read('./scripts/lib/base_openapi.json'))
event_schemas.each do |path|
  json = JSON.parse(File.read(path))
  openapi['components']['schemas'].merge!(json['definitions'])
end

# Remove orphan schemas
loop do
  defined = openapi['components']['schemas'].keys.grep_v(/.+Event$/)
  referenced = openapi.to_json.scan(%r{"#/components/schemas/([^"]+)"}).flatten.uniq
  orphans = defined - referenced
  break if orphans.empty?

  orphans.each do |orphan|
    openapi['components']['schemas'].delete(orphan)
  end
end

File.write(File.join(tmp_dir, 'Events', 'openapi.json'), JSON.pretty_generate(openapi))
