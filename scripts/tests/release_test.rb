# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../release'

class ReleaseTest < Minitest::Test
  def test_valid_calver
    assert valid_calver?('2026.7.0')
    assert valid_calver?('2026.12.14')

    refute valid_calver?('v2026.7.0')
    refute valid_calver?('2026.07.0')
    refute valid_calver?('2026.13.0')
    refute valid_calver?('0.12.0')
  end

  def test_generate_release_notes_uses_matching_changelog_section
    Tempfile.create('changelog') do |file|
      file.write(<<~CHANGELOG)
        # Changelog

        ## Unreleased

        ## [2026.7.1] - 2026-07-18

        ### Fixed

        * Hardened release publication - #123

        ## [2026.7.0] - 2026-07-02

        * Previous release
      CHANGELOG
      file.flush

      notes = generate_release_notes('2026.7.1', nil, file.path)

      assert_equal <<~NOTES, notes
        # 2026.7.1

        ### Fixed

        * Hardened release publication - #123
      NOTES
    end
  end

  def test_generate_release_notes_requires_matching_section
    Tempfile.create('changelog') do |file|
      file.write("# Changelog\n\n## Unreleased\n")
      file.flush

      assert_raises(SystemExit) do
        generate_release_notes('2026.7.1', nil, file.path)
      end
    end
  end
end
