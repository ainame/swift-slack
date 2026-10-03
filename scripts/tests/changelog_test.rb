# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/changelog'

class ChangelogTest < Minitest::Test
  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Changed

    * Unreleased change - #3

    ## [2026.10.1] - 2026-10-01

    Follow-up release.

    ### Changed

    * Second change - #2

    ## [2026.10.0] - 2026-10-01

    ### Fixed

    * First fix - #1
  MARKDOWN

  def test_changelog_section_returns_body_up_to_next_version
    assert_equal "Follow-up release.\n\n### Changed\n\n* Second change - #2", changelog_section(CHANGELOG, '2026.10.1')
  end

  def test_changelog_section_returns_last_section_to_end_of_file
    assert_equal "### Fixed\n\n* First fix - #1", changelog_section(CHANGELOG, '2026.10.0')
  end

  def test_changelog_section_does_not_match_version_prefix
    assert_nil changelog_section(CHANGELOG, '2026.10')
  end

  def test_changelog_section_returns_nil_for_missing_version
    assert_nil changelog_section(CHANGELOG, '2026.11.0')
  end

  def test_changelog_section_returns_nil_for_empty_section
    assert_nil changelog_section("## [2026.11.0] - 2026-11-01\n\n## [2026.10.1] - 2026-10-01\n\n* Change\n", '2026.11.0')
  end
end
