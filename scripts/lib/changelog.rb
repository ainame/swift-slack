# frozen_string_literal: true

# Return the body of the `## [version]` section of a CHANGELOG.md, or nil when it is missing or empty
def changelog_section(changelog, version)
  lines = changelog.lines
  start = lines.index { |line| line.start_with?("## [#{version}]") }
  return nil unless start

  body = lines[(start + 1)..].take_while { |line| !line.start_with?('## ') }.join.strip
  body.empty? ? nil : body
end
