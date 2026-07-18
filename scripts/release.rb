#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'English'
require 'tempfile'

def main
  auto_confirm = ARGV.delete('--yes')
  abort 'Usage: ruby scripts/release.rb [YYYY.M.PATCH] [--yes]' if ARGV.length > 1

  check_prerequisites
  run!('git', 'fetch', '--prune', '--tags', 'origin', 'main')
  ensure_releasable_main!

  new_tag, latest_tag = get_version(ARGV.first)
  ensure_release_does_not_exist!(new_tag)
  release_notes = generate_release_notes(new_tag, latest_tag)

  unless auto_confirm
    print "Publish release #{new_tag} from #{capture!('git', 'rev-parse', '--short', 'HEAD').strip}? (y/N): "
    exit unless STDIN.gets.to_s.strip.downcase == 'y'
  end

  run!('swift', 'build')
  run!('swift', 'test')

  notes_file = Tempfile.new(["swift-slack-#{new_tag}-", '.md'])
  notes_file.write(release_notes)
  notes_file.close

  begin
    run!('git', 'tag', '-a', new_tag, '-m', "Release #{new_tag}")
    run!('git', 'push', 'origin', new_tag)
    run!('gh', 'release', 'create', new_tag, '--verify-tag', '--title', new_tag, '--notes-file', notes_file.path)
  rescue SystemExit
    warn "Release publication failed. Inspect the local and remote #{new_tag} tag before retrying."
    raise
  ensure
    notes_file.unlink
  end

  verify_release!(new_tag)
  repo = capture!('gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner').strip
  puts "\nRelease published: https://github.com/#{repo}/releases/tag/#{new_tag}"
end

def check_prerequisites
  abort 'Error: GitHub CLI not authenticated. Run: gh auth login' unless system('gh', 'auth', 'status', out: File::NULL, err: File::NULL)
  abort 'Error: Uncommitted changes. Please commit or stash first.' unless capture!('git', 'status', '--porcelain').empty?
end

def ensure_releasable_main!
  branch = capture!('git', 'branch', '--show-current').strip
  abort "Error: Releases must be published from main, not #{branch.empty? ? 'a detached HEAD' : branch}." unless branch == 'main'

  head = capture!('git', 'rev-parse', 'HEAD').strip
  origin_main = capture!('git', 'rev-parse', 'origin/main').strip
  abort "Error: main is not synchronized with origin/main.\nHEAD:        #{head}\norigin/main: #{origin_main}" unless head == origin_main
end

def ensure_release_does_not_exist!(tag)
  tag_exists = system('git', 'rev-parse', '--quiet', '--verify', "refs/tags/#{tag}", out: File::NULL, err: File::NULL)
  abort "Error: Tag #{tag} already exists." if tag_exists

  release_exists = system('gh', 'release', 'view', tag, out: File::NULL, err: File::NULL)
  abort "Error: GitHub release #{tag} already exists." if release_exists
end

def get_version(version = nil)
  latest_tag = latest_calver_tag
  puts "Latest CalVer tag: #{latest_tag || 'none'}"

  if version.nil?
    print "New version (e.g., #{suggest_next_calver}): "
    version = STDIN.gets.to_s.strip
  end

  abort "Invalid version format. Use YYYY.M.PATCH, for example #{suggest_next_calver}" unless valid_calver?(version)

  [version, latest_tag]
end

def valid_calver?(version)
  version&.match?(/\A\d{4}\.([1-9]|1[0-2])\.\d+\z/)
end

def latest_calver_tag
  capture!('git', 'tag', '--list').lines.map(&:strip).select { valid_calver?(_1) }.max_by do |tag|
    tag.split('.').map(&:to_i)
  end
end

def suggest_next_calver(today = Date.today)
  prefix = "#{today.year}.#{today.month}."
  patches = capture!('git', 'tag', '--list', "#{prefix}*").lines.filter_map do |line|
    line.strip[/\A#{Regexp.escape(prefix)}(\d+)\z/, 1]&.to_i
  end

  "#{prefix}#{patches.empty? ? 0 : patches.max + 1}"
end

def generate_release_notes(new_tag, latest_tag, changelog_path = 'CHANGELOG.md')
  lines = File.readlines(changelog_path)
  heading = /\A## \[#{Regexp.escape(new_tag)}\](?: - .+)?\s*\z/
  start_index = lines.index { _1.match?(heading) }
  abort "Error: CHANGELOG.md has no release section for #{new_tag}." unless start_index

  end_index = ((start_index + 1)...lines.length).find { lines[_1].start_with?('## ') } || lines.length
  section = lines[(start_index + 1)...end_index].join.strip
  abort "Error: CHANGELOG.md release section for #{new_tag} is empty." if section.empty?

  notes = ["# #{new_tag}", '', section]
  notes += ['', "**Full Changelog**: #{comparison_url(latest_tag, new_tag)}"] if latest_tag
  notes.join("\n") + "\n"
end

def comparison_url(latest_tag, new_tag)
  repo = capture!('gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner').strip
  "https://github.com/#{repo}/compare/#{latest_tag}...#{new_tag}"
end

def verify_release!(tag)
  head = capture!('git', 'rev-parse', 'HEAD').strip
  tagged_commit = capture!('git', 'rev-parse', "#{tag}^{}").strip
  abort "Error: #{tag} points to #{tagged_commit}, expected #{head}." unless tagged_commit == head

  run!('gh', 'release', 'view', tag, '--json', 'url,tagName,isDraft,isPrerelease')
end

def run!(*command)
  return if system(*command)

  abort "Command failed: #{command.join(' ')}"
end

def capture!(*command)
  output = IO.popen(command, err: [:child, :out], &:read)
  abort "Command failed: #{command.join(' ')}\n#{output}" unless $CHILD_STATUS.success?

  output
end

main if __FILE__ == $PROGRAM_NAME
