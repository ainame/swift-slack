---
name: slack-upstream-sync
description: Sync swift-slack's two upstream vendor snapshots, review generated and handwritten model changes, repair generation or model defects, verify, and prepare a PR. Use for scheduled or manual upstream catch-up; release publication is separate.
---

# Slack Upstream Sync

Keep the existing Make targets as the reproducible execution path. Read `AGENTS.md`
for fixture eligibility, handwritten model wiring, ownership, and required checks.

## Access and basis

- Scheduled runs must be configured with full access, network access, and working
  Git/GitHub credentials. A skill cannot override its execution permissions. Check
  `gh auth status`, fetch `origin/main`, and query both upstream remote HEADs early.
  Report access failures as blockers; never infer that upstream is unchanged.
- Inspect status, including initialized submodules, before changes. Preserve user
  work. Use an isolated clean worktree and an agent-prefixed branch from freshly
  fetched `origin/main`; repair detached checkouts or uninitialized submodules rather than
  stopping at recoverable setup issues. Do not reset or clean a checkout containing
  unrelated changes. Do not run `make clean` for setup recovery.
- Check open schema-update/sync PRs, including `automated/schema-update`. Reuse the
  relevant branch when its ownership and contents are clear; otherwise report the
  overlap and stop before creating a competing PR. Fetch the branch and inspect its
  existing changes before updating it. Do not force-push another author's work.
- Record both old gitlinks from current `origin/main` and read `UPSTREAM.md`.
  Initialize vendor checkouts at their pins, then use `make update` to advance their
  upstream branches. This sync follows branch snapshots, not Java release tags.
  Record exact new SHAs and inspect ancestry; investigate divergence rather than
  treating it as an ordinary forward update.

## Review and implementation

Compare each old/new vendor snapshot before and after generation. Review the full
delta, routing changes by relevance: response fixtures, method arguments, Events,
Java model classes, Block Kit, and applicable handwritten runtime behavior. Consult
upstream examples/tests when behavior is ambiguous. Java-only tooling or unrelated
implementation changes can be excluded with a reason.

Run `bundle install` and `make generate`. Generation failures are fatal:
do not ship partial output or bypass the failing command. Fix owning specs/scripts
or handwritten models, then rerun the complete generation pass. Review additions,
deletions, generated traits in `Package.swift`, and all three generated trees.

For new or changed API families and payloads:

- Response and event types come from the Java classes, so review changed Java model,
  response and event classes field by field against the generated Swift types.
  Generation fails on Java constructs it cannot translate, on unresolved type names,
  on a new Gson adapter without a decision in `scripts/lib/java_openapi/gson_adapters.rb`,
  on stale or unused entries in `scripts/java_type_overrides.yml` and
  `scripts/handwritten_schemas.yml`, and on shared model names that clash with
  existing top-level types. Fix the cause rather than suppressing the check.
- Run `make check-fixtures`. Every generated method's and event's fixture must decode,
  and every fixture value that contradicts its schema needs a reviewed entry in
  `scripts/java_type_overrides.yml`. Mismatches only in slack-api-ref documentation
  examples are informational.
- Compilation and successful decoding can hide silent field loss. Check fixture keys
  that the Java classes do not declare; add an `added` override only when recorded
  responses carry the field.
- Follow `AGENTS.md` for the type override and hand-written schema rules. Do not
  hand-edit generated files or infer Web API responses from Slack reference
  documentation examples.
- Inspect handwritten Block Kit and Events changes even if generation is unchanged.
  Explicitly assess additions/removals that affect exhaustive switches or public API.

Decide whether work is needed from the reviewed upstream delta, not generated-file
changes alone. Do not make vendor-only PRs for irrelevant churn by default. If no
applicable change exists, leave the repository pins unchanged and report a verified
no-op without committing the temporary vendor advancement.

For scheduled no-op runs, persist the reviewed-through SHA for each upstream in the
run memory, together with the origin/main SHA, coverage decisions and known gaps.
On later runs, reuse that review only if origin/main and the review policy are
unchanged and each recorded SHA is an ancestor of the current upstream head. Review
new commits and reconsider unresolved gaps when either upstream supplies missing
inputs. Otherwise review from the repository pins again. Never advance vendor pins
merely to suppress irrelevant churn. A no-op requires live access even when prior
coverage is reused.

Keep sync fixes focused on the owning generator/model defect. Unrelated refactors
belong in a separate PR unless the user explicitly requests them during the sync;
explain any such authorized additions in the PR body.

## Verification and PR

- Run `swift test` for a sync. Run `make test-scripts` when scripts change, in addition
  to the full generation pass. Confirm reproducibility by rerunning `make generate`
  against the final pins and comparing output with the first completed pass; explain
  any drift. Finish with `git diff --check`.
- Use the versions recorded in `.swift-version` and `.ruby-version`. Distinguish
  environment failures from code defects. Keep unresolved verification visible;
  never call an unverified sync successful.
- Update `UPSTREAM.md` with both old/new SHAs, review date, reviewed areas, decisions,
  exclusions, and unresolved gaps. Preserve its structural sections, including
  "Maintaining this record". Do not put hosted CI status in committed files.
  Use [update-changelog](../update-changelog/SKILL.md) for notable consumer and
  contributor changes; consolidate the complete PR's entries after follow-ups,
  put significant contributor improvements in Maintenance, and omit housekeeping.
  Update README only for user-facing scope changes.
- Commit focused changes, push the branch, and open or update the sync PR. Use
  `gh pr create/edit --body-file` for multiline Markdown. Open the PR first to obtain
  its number, then add notable `Unreleased` notes when applicable and the
  provenance PR reference in a follow-up commit. Attach the PR using the host’s
  artifact tool when available. Use `schema-update` as the sole PR label; remove other labels when
  updating a sync PR.
- Use the dated title `Update Slack API schemas (YYYY-MM-DD)` with the review date.
  Write short bullets beneath `####` change headings (operations, models, generator,
  coverage gaps, verification); identify additions, changes and removals explicitly.
  Avoid tables in the PR body. Refresh hosted-check notes when their verified status
  changes, and never predict that a pending run will pass.
- Explain implemented changes, handwritten model decisions, exclusions, breaking
  changes, and validation. Separate local checks from hosted CI and live Slack
  testing. If push or PR creation fails, preserve commits and report the exact
  blocker. A partially resolved sync may be a draft PR with explicit remaining work.
- Leave merge and release publication for separate user instructions. Stay quiet on
  scheduled runs with no actionable change; notify for a PR, failure, or needed input.

Completion means every relevant change in the selected delta is implemented,
already supported, or intentionally excluded with a reason; generation is
reproducible and required checks pass. Report unresolved changes as incomplete.
