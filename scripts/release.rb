#!/usr/bin/env ruby
require 'json'
require 'date'
require 'tempfile'
require 'time'
require_relative 'lib/changelog'

def main
  check_prerequisites

  args = ARGV.dup
  auto_confirm = args.delete('--yes')

  # Accept version as argument
  version = args[0]
  new_tag, latest_tag = get_version(version)

  # Release notes come from the version's CHANGELOG.md section; check it before tagging
  notes = release_notes(new_tag)

  # Confirm (skip if --yes provided)
  unless auto_confirm
    print "Create release #{new_tag}? (y/N): "
    exit unless STDIN.gets.to_s.strip.downcase == 'y'
  end

  system('swift build') or abort "Build failed"
  system('swift test') or abort "Tests failed"

  # Create tag and release
  system("git tag -a #{new_tag} -m 'Release #{new_tag}'")
  system("git push origin #{new_tag}")

  Tempfile.create(["release-notes-#{new_tag}", '.md']) do |file|
    file.write(notes)
    file.flush
    system("gh release create #{new_tag} --title 'Release #{new_tag}' --notes-file #{file.path} --draft")
  end

  puts "\n✅ Draft release created! Review at: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases"
end

# Check prerequisites
def check_prerequisites
  unless system('gh', 'auth', 'status', out: File::NULL, err: File::NULL)
    abort "Error: GitHub CLI not authenticated. Run: gh auth login"
  end

  unless `git status --porcelain`.empty?
    abort "Error: Uncommitted changes. Please commit or stash first."
  end
end

# Get version from user
def get_version(version = nil)
  latest_tag = `git describe --tags --abbrev=0 2>/dev/null`.strip
  puts "Latest tag: #{latest_tag.empty? ? 'none' : latest_tag}"

  if version.nil?
    print "New version (e.g., #{suggest_next_calver}): "
    version = STDIN.gets.to_s.strip
  end

  unless valid_calver?(version)
    abort "Invalid version format. Use YYYY.M.PATCH, for example #{suggest_next_calver}"
  end

  [version, latest_tag]
end

def valid_calver?(version)
  version =~ /^\d{4}\.([1-9]|1[0-2])\.\d+$/
end

def suggest_next_calver(today = Date.today)
  year = today.year
  month = today.month
  prefix = "#{year}.#{month}."
  patches = `git tag --list '#{prefix}*'`
    .lines
    .map(&:strip)
    .map { |tag| tag[/^#{Regexp.escape(prefix)}(\d+)$/, 1] }
    .compact
    .map(&:to_i)

  "#{prefix}#{patches.empty? ? 0 : patches.max + 1}"
end

# Use the version's CHANGELOG.md section as the release notes
def release_notes(new_tag)
  section = changelog_section(File.read('CHANGELOG.md', encoding: 'UTF-8'), new_tag)
  abort "Error: CHANGELOG.md has no non-empty '## [#{new_tag}]' section. Merge the release-preparation PR first." unless section

  section + "\n"
end

# Run main
main if __FILE__ == $0
