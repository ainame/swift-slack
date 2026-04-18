---
name: renovate-swiftformat-pr
description: Handle Renovate pull requests in this `swift-slack` repository that update SwiftFormat or formatter wiring. Use when Codex needs to check out a Renovate PR here, run this repo's formatter workflow starting with `make format`, apply any remaining direct SwiftFormat fixes to touched files, run `swift build` or `swift test` as appropriate, commit the formatting-only follow-up, and push it back to the PR branch.
---

# Renovate SwiftFormat PR

## Overview

Use this skill to finish `swift-slack` Renovate PRs that bump `nicklockwood/SwiftFormat` or related formatter wiring. The goal is to apply the repository's normal formatting flow first, validate the result with the repo's documented Swift commands, and push a small follow-up commit back to the PR branch without disturbing unrelated work.

## Inputs

- PR URL or PR number
- Local repository checkout with git access
- Repository formatter configuration, usually `.swiftformat`
- Repository conventions from `AGENTS.md`, especially `make format`, `swift build`, and `swift test`

## Workflow

1. Resolve the PR head branch and repository.
   - Read `git status -sb` and confirm the worktree is clean enough to operate safely.
   - Inspect the PR metadata to get the exact `head.ref` and `head.repo.clone_url`.
   - Prefer `gh pr view <number> --json headRefName,headRepository,headRepositoryOwner,url` when `gh` is authenticated.
   - If `gh` auth is unavailable, use the public GitHub API with `curl https://api.github.com/repos/<owner>/<repo>/pulls/<number>` and read `head.ref` plus `head.repo.clone_url`.
   - Do not assume the local `origin` remote matches the PR repository.
2. Check out the PR branch locally.
   - Fetch the PR head into a temporary local branch, for example `git fetch <clone_url> pull/<number>/head:pr-<number>`.
   - Switch to that local branch.
   - Re-check `git status -sb` before formatting.
3. Identify the files that need formatting.
   - Inspect the PR diff against its base branch.
   - Prefer formatting only the Swift files and `Package.swift` changed by the PR or by the formatter follow-up.
   - Ignore markdown-only changes unless the repository has a formatter step that intentionally rewrites them.
4. Run the repository-native formatter path first.
   - In this repository, start with `make format`.
   - Treat `make format` as the default formatter entrypoint because it captures the repo's preferred SwiftFormat plugin invocation.
   - Use another repo-native entrypoint only if the repository instructions change.
5. Fall back to direct `swiftformat` when the native path misses the touched files.
   - Inspect the formatter result with `git diff --stat`.
   - If `make format` reports success but leaves touched Swift files unchanged because its target scope excludes them, run the installed `swiftformat` binary directly on the changed file set.
   - Prefer `swiftformat --config .swiftformat <changed-files...>` when a repo config exists.
6. Validate the formatted result.
   - Follow this repository's guidance from `AGENTS.md`.
   - Prefer `swift build` for a formatting-only follow-up and run `swift test` when the repository instructions or the actual code changes make that necessary.
   - Treat existing upstream warnings as informational unless the build fails.
7. Commit only the formatting follow-up.
   - Stage only the formatter-edited files.
   - Use a terse commit message such as `Apply SwiftFormat to Renovate update`.
   - Do not mix unrelated local changes into the commit.
8. Push back to the PR head branch.
   - Push to the actual PR head repo and ref, even if local `origin` points somewhere else.
   - Prefer `git push <head.repo.clone_url> HEAD:<head.ref>` when the remote configuration is ambiguous.
   - Confirm the push updated the PR head SHA.

## Guardrails

- Do not push to `main` or another default branch.
- Do not assume the repo's `make format` target covers every Swift source tree.
- Do not skip `make format` and jump straight to direct `swiftformat` unless you have already confirmed the repo entrypoint is insufficient for the changed files.
- Do not rewrite the PR beyond formatter output unless the user explicitly asks for code fixes.
- Do not use `git add -A` when the worktree contains unrelated changes.
- Do not force-push unless the user explicitly requests it and it is necessary.
- Keep the follow-up commit formatting-only.

## Useful Commands

- `git status -sb`
- `git diff --stat <base>...HEAD`
- `gh pr view <number> --json headRefName,headRepository,headRepositoryOwner,url`
- `curl -fsSL https://api.github.com/repos/<owner>/<repo>/pulls/<number>`
- `git fetch <clone_url> pull/<number>/head:pr-<number>`
- `git checkout pr-<number>`
- `make format`
- `swiftformat --config .swiftformat <files...>`
- `swift build`
- `swift test`
- `git add <files...>`
- `git commit -m "Apply SwiftFormat to Renovate update"`
- `git push <clone_url> HEAD:<head.ref>`

## Output

Report:

- Which formatter command changed the files
- Which validation command ran
- The follow-up commit SHA
- The exact PR branch that received the push
