---
name: update-changelog
description: Write or consolidate swift-slack CHANGELOG.md entries from a PR's complete final diff, focusing on library consumers. Use when adding release notes or revising an existing PR's changelog after follow-up commits.
---

# Update Changelog

Write release notes for people using swift-slack. Summarize the final effect of a
whole PR, rather than its commits or the sequence of review fixes.

## Choose what belongs

- Include public API additions/removals, observable behavior changes, decoding or
  encoding fixes, compatibility changes, and dependency/platform changes that
  affect consumers. Explain the concrete benefit or migration requirement.
- Agent instructions, skills, PR labels, CI housekeeping, tests, formatting, and
  internal tooling/refactors do not warrant entries by themselves. Include a
  consumer effect when one exists, not the maintenance work that produced it.
  Consumer-relevant build or dependency changes still belong even when implemented
  in tooling or CI.
- A PR with no consumer-facing effect needs no changelog entry. Record its scope
  and validation in the PR description instead.
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
remove duplication and maintenance-only notes, and remove claims superseded by
later commits. Do not append a new bullet merely because another commit landed.
Keep distinct consumer effects separate when that makes the notes clearer; one
bullet per PR is not a requirement.

Preserve other PRs' entries and published release sections unless their cleanup is
explicitly requested. If an entry covers multiple PRs, preserve the other PRs'
consumer effects and references while changing the current PR's contribution.

## Write and check

- Use the existing past tense, `*` bullets, and contiguous lists. Keep applicable
  sections in Added, Changed, Fixed order, and omit empty sections.
- Use Added for new public capabilities, Changed for altered existing behavior or
  compatibility, and Fixed for defects. State the user-visible result rather than
  the generator implementation. Mark breaking changes with `**BREAKING**:` and
  explain what consumers must change.
- End each bullet with its PR reference, for example `- #149`. Identify important
  public names and affected fields without enumerating every internal file.
- Keep transient hosted CI status, local paths, verification logs, and review
  history out of the changelog. Those belong in the PR description.
- Re-read all entries for the PR together: do they explain what consumers gain,
  what was fixed, and any required migration without repeating the same result?
  Compare their claims with the final diff and run `git diff --check`.

For example, a conversation schema merge fix is useful as “Fixed conversation
response decoding that discarded mention restrictions and channel workflows.”
The merge helper, regression tests, and agent-skill edits are not separate release
notes. Follow `AGENTS.md` for commits and the existing release skill for publication;
editing the changelog does not authorize a release.
