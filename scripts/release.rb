#!/usr/bin/env ruby
require 'json'
require 'date'
require 'time'

def main
  check_prerequisites

  args = ARGV.dup
  auto_confirm = args.delete('--yes')

  # Accept version as argument
  version = args[0]
  new_tag, latest_tag = get_version(version)

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

  changelog = generate_changelog(new_tag, latest_tag)
  File.write("CHANGELOG_#{new_tag}.md", changelog)

  system("gh release create #{new_tag} --title 'Release #{new_tag}' --notes-file CHANGELOG_#{new_tag}.md --draft")
  File.delete("CHANGELOG_#{new_tag}.md")

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

# Generate changelog
def generate_changelog(new_tag, latest_tag)
  puts "Generating changelog..."

  # Get merged PRs
  search = latest_tag.empty? ? "" : "merged:>#{`git log -1 --format=%ai #{latest_tag}`.strip}"
  prs = JSON.parse(`gh pr list --state merged --limit 100 --search "#{search}" --json number,title,author`)

  changelog = ["# Release #{new_tag}", "", "## What's Changed", ""]
  changelog += prs.map { |pr| "* #{pr['title']} by @#{pr['author']['login']} in ##{pr['number']}" }

  # Contributors
  contributors = prs.map { |pr| pr['author']['login'] }.uniq.sort
  changelog += ["", "## Contributors", ""] + contributors.map { |c| "* @#{c}" }

  unless latest_tag.empty?
    repo = JSON.parse(`gh repo view --json nameWithOwner`)['nameWithOwner']
    changelog << ""
    changelog << "**Full Changelog**: https://github.com/#{repo}/compare/#{latest_tag}...#{new_tag}"
  end

  changelog.join("\n")
end

# Run main
main if __FILE__ == $0
