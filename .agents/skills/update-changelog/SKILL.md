---
name: update-changelog
description: Write or consolidate swift-slack CHANGELOG.md entries from a PR's complete final diff, covering notable changes for library consumers and contributors. Use when adding release notes or revising an existing PR's changelog after follow-up commits.
---

# Update Changelog

Write changelog entries for swift-slack users and contributors. Summarize the final
effect of a whole PR, rather than its commits or the sequence of review fixes.

## Keep a Changelog principles

These guidelines follow [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/),
with conventions specific to swift-slack. See [attribution and license notice](NOTICE.md).

- Curate noteworthy outcomes for users and contributors; write plainly rather than
  turning each commit into an entry. Review automated drafts against actual changes.
- Group entries under Added (capabilities), Changed (intentional behavior changes),
  Deprecated (planned retirement), Removed (removal), Fixed (incorrect behavior),
  or Security (vulnerabilities). Omit empty groups. Lead security notes with the CVE
  identifier when available.
- Highlight compatibility breaks within their category. Give short migration steps
  inline; link substantial instructions. Announce deprecations before removal,
  stating the planned removal version when known.
- Keep `Unreleased` first, then releases newest first with `YYYY-MM-DD` dates.
  Link version headings to tag comparisons; use the initial tag for the first
  release and latest-tag-to-HEAD for Unreleased. Use verified refs.
- Keep the preamble's convention version pinned and state the versioning scheme.
  Use the repository changelog as the source for release announcements.
- Include all significant changes consistently; omit trivia. Preserve withdrawn
  versions with `[YANKED]`. Correct inaccurate history within the requested scope.

Repository adaptations: swift-slack uses CalVer `YYYY.M.PATCH`, without `v`-prefixed
tags; its PATCH counter does not signal API compatibility. Keep `**BREAKING**:`
markers explicit. Keep a Changelog recommends six categories; our optional
`Maintenance` section is a deliberate extension for notable contributor outcomes,
placed last. Our required bare PR references also remain a repository convention.

## Choose what belongs

- Include public API additions/removals, observable behavior changes, decoding or
  encoding fixes, compatibility changes, and dependency/platform changes that
  affect consumers. Explain the concrete benefit or migration requirement.
- Put notable improvements to generation, development, or contribution workflows
  in `Maintenance`, explaining their value to contributors. Internal tooling or
  refactoring belongs there only when the outcome is worth knowing about.
- PR labels, formatting churn, routine CI housekeeping, individual test additions,
  and minor agent-instruction edits do not warrant entries by themselves. Build
  and dependency changes affecting consumers belong in the standard categories,
  even when implemented through tooling or CI.
- A PR with no notable consumer or contributor effect needs no entry. Record its
  scope and validation in the PR description instead.
- Name the repository when discussing models or fields: `java-slack-sdk` fixtures
  and Java models, `slack-api-ref` schemas, or `swift-slack` generated/handwritten
  types. An upstream addition is not a downstream feature until swift-slack exposes
  or supports it. Do not claim complete upstream parity from a reviewed delta.

## Review the PR as a whole

Read the relevant `Unreleased` entries, the complete PR diff against its base, and
its current description. Confirm the PR number; do not invent one. When the PR has
not been opened, prepare the wording and add its reference after opening it within
existing authorization.

Find every existing `Unreleased` bullet for this PR, including nested detail.
Rewrite that set to describe the final delivered changes: combine related bullets,
remove duplication and routine housekeeping, and remove claims superseded by
later commits. Apply this consolidation to Maintenance entries too. Do not append
a new bullet merely because another commit landed.
Keep distinct reader-relevant effects separate when that makes the notes clearer; one
bullet per PR is not a requirement.

Preserve other PRs' entries and published release sections unless their cleanup is
explicitly requested. If an entry covers multiple PRs, preserve the other PRs'
effects and references while changing the current PR's contribution.

## Write and check

- Use the existing past tense, `*` bullets, and contiguous lists. Keep applicable
  sections in Added, Changed, Deprecated, Removed, Fixed, Security, Maintenance
  order, and omit empty sections.
- Describe the reader-visible result. Use the repository's `**BREAKING**:` marker
  for compatibility breaks and explain what consumers must change.
- End each bullet with its PR reference, for example `- #149`. Identify important
  public names and affected fields without enumerating every internal file.
- Keep transient hosted CI status, local paths, verification logs, and review
  history out of the changelog. Those belong in the PR description.
- Re-read all entries for the PR together: do they explain what consumers gain,
  what was fixed, any required migration, and notable contributor improvements
  without repeating the same result?
  Compare their claims with the final diff and run `git diff --check`.

For example, a conversation schema merge fix is useful as “Fixed conversation
response decoding that discarded mention restrictions and channel workflows.”
The merge helper and regression tests are not separate release notes. A distinct
contributor improvement can use one Maintenance bullet, such as “Simplified
handwritten model overrides by discovering source files and sharing extraction
logic.” Label changes still need no entry. Follow `AGENTS.md` for commits and the
existing release skill for publication;
editing the changelog does not authorize a release.
