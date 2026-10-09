#!/usr/bin/env ruby

require_relative 'lib/code_generation/slackmodels_extractor'

# Repository sources are UTF-8; do not depend on the caller's locale.
Encoding.default_external = Encoding::UTF_8

if ARGV.length < 2
  puts "Usage: ruby extract_slackmodels.rb <types_file> <output_dir>"
  exit 1
end

SlackModelsExtractor.new(ARGV[0], ARGV[1]).extract
