---
name: release-new-version
description: Prepare and publish a new swift-slack repository release when the user asks to bump a version, adopt or apply CalVer, update release files, update the changelog, create or move a git tag, push release refs, or create or edit a GitHub release. Use for release tasks that must happen through a PR and then from the latest synced `main` branch, with `YYYY.M.PATCH` version tags that do not use a `v` prefix.
---

# Release New Version

## Overview

Use this skill to perform the full release flow safely: choose the CalVer version, update release-facing files, update `CHANGELOG.md`, commit release metadata through a PR, ensure the release commit is on the latest `main`, create or move the version tag, push the tag, and create or update the GitHub release page.

Treat `main` as the only valid source for release tags. Prepare release metadata on a branch and PR when files need to change. After the PR is merged, switch to `main`, sync it with `origin/main`, and publish the tag/release from that merged commit.

## Versioning

- Use calendar versioning in the form `YYYY.M.PATCH`, for example `2026.7.0`.
- Use the calendar date in the release timezone/current environment to choose `YYYY` and `M`.
- Do not zero-pad the month. `2026.7.0` is valid; `2026.07.0` is not.
- Treat `PATCH` as the release counter within the month, not as a SemVer compatibility signal.
- Use `PATCH = 0` for the first release in a month. Increment it for additional releases in the same month.
- Reset `PATCH` to `0` when the month changes.
- Never prepend `v` to tags.
- Call out breaking changes explicitly in `CHANGELOG.md`; the version number does not encode source compatibility.

## Inputs

- Release version, for example `2026.7.0`; if omitted, infer the next `YYYY.M.PATCH` from the current date and existing tags
- Repository checkout with git and `gh` configured
- Release notes source, usually `CHANGELOG.md`

## Workflow

1. Verify repository state and choose a release branch.
   - Run `git status --short --branch`.
   - Confirm the local base branch matches `origin/main`. If it does not, update from `origin/main` before changing release metadata.
   - Create or switch to a release preparation branch such as `codex/release-2026-7-0` unless the user explicitly asks only for local edits.
2. Inspect release context.
   - Read the current `CHANGELOG.md`.
   - Inspect commits since the previous tag or release version so the changelog entry matches the actual release scope.
   - Check whether the target tag already exists locally or remotely.
   - Check whether a GitHub release for that tag already exists.
3. Update release-facing files before tagging.
   - Convert the unreleased section into a dated release section, or add a new release section if the changelog format differs.
   - Keep the version string exact and never prepend `v`.
   - Keep the changelog aligned with the commits that will actually be on the tagged `main` commit.
   - Update README package dependency examples to the new release version.
   - Keep `AGENTS.md` and this skill aligned with the CalVer policy if the policy changes.
   - Keep `scripts/release.rb` validating `YYYY.M.PATCH` and suggesting the next monthly release counter.
4. Verify only when needed.
   - If the release changes code, generated artifacts, dependencies, or anything beyond release metadata, run `swift build` and then `swift test`.
   - Keep that order so build failures surface before the slower test pass.
   - If the change is changelog-only or release-metadata-only, verification can be skipped and that should be stated explicitly.
5. Commit the release metadata on the release preparation branch.
   - Create a dedicated commit such as `Prepare <version> release`.
   - Push the branch and open a PR. Do not push directly to `main`.
6. After the PR merges, publish from `main`.
   - Switch to `main`.
   - Fetch and fast-forward to `origin/main`.
   - Confirm the release metadata commit is present on `main`.
   - Push `main` only when required by the release flow and permitted by branch protection; otherwise rely on the merged PR.
7. Create or correct the tag.
   - Create an annotated tag named exactly `<version>`.
   - Never use a `v` prefix.
   - If the tag already exists on the wrong commit, move it only after the correct `main` commit exists, then force-push the tag update.
8. Publish or correct the GitHub release.
   - If no release exists, create it from the tag with notes sourced from the new changelog section.
   - If a release already exists, edit it so the notes and tag reference stay aligned with the corrected tag.
9. Re-check final state.
   - Confirm `HEAD`, `origin/main`, and `<version>^{}` resolve to the same commit.
   - Confirm the GitHub release URL and whether it is a draft or prerelease.

## Guardrails

- Do not publish release tags from feature branches, topic branches, or detached HEAD states.
- Do not push release metadata directly to `main`; use a branch and PR.
- Do not tag before the changelog update is committed.
- Do not use SemVer-style versions such as `0.12.0` for new releases.
- Do not assume an existing release tag is correct; inspect it.
- Prefer editing an existing GitHub release instead of creating duplicates.
- If branch protection messages appear during push, report them, but continue only if the push actually succeeds.

## Useful Commands

- `git status --short --branch`
- `git checkout -b codex/release-<version-with-dashes>`
- `git rev-parse HEAD && git rev-parse origin/main`
- `git log --oneline <previous-tag>..main`
- `ruby scripts/release.rb <version> --yes`
- `swift build`
- `swift test`
- `git tag --list`
- `gh release view <version> --json url,targetCommitish,tagName,name,isDraft,isPrerelease`
- `git tag -a <version> -m "<version>"`
- `git tag -fa <version> -m "<version>"`
- `git push origin main`
- `git push origin <version>`
- `git push --force origin <version>`
- `gh release create <version> --title "<version>" --notes-file <path>`
- `gh release edit <version> --title "<version>" --notes-file <path>`

## Output

Report:
- The release commit SHA on `main`
- Whether verification was run
- Whether the tag was newly created or moved
- The GitHub release URL
