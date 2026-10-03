#!/usr/bin/env ruby

require_relative 'lib/code_generation/slackmodels_extractor'

if ARGV.length < 2
  puts "Usage: ruby extract_slackmodels.rb <types_file> <output_dir>"
  exit 1
end

SlackModelsExtractor.new(ARGV[0], ARGV[1]).extract
