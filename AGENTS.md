# AGENTS.md

Shared guidance for coding agents working in this repository, a Swift Slack SDK and app framework: generated Web API and model layers plus a handwritten runtime for interactive Slack apps over Socket Mode or signed HTTP requests. This file holds the rules and constraints the code does not show; read the code, `Package.swift`, the `Makefile`, and the README for everything else.

## Repository Conventions

- Do not push directly to `main`; use branches and PRs.
- Inspect `git status` before editing or staging. Preserve unrelated user changes and stage only files that belong to the current task.
- Make a focused git commit for each meaningful change.
- Prefer changing the owning source, generator, or handwritten runtime layer instead of patching downstream symptoms.
- Keep PR descriptions and verification notes free of user-specific absolute paths or local environment details.
- When discussing models or fields, explicitly name the repository: upstream `java-slack-sdk` models/fixtures, upstream `slack-api-ref` schemas/definitions, or downstream `swift-slack` generated/handwritten models. Attribute additions, changes, omissions, dates, and snapshots to that repository so their origin is clear.
- PRs with library-consumer changes update `## [Unreleased]` in `CHANGELOG.md`; maintenance-only PRs need no entry. Use `.agents/skills/update-changelog/SKILL.md` to review and consolidate the complete PR’s entries after follow-up commits. Mark breaking changes with `**BREAKING**:` and end each bullet with its PR reference, such as `- #123`; open the PR first to get its number.
- Do not use `swift-actions/setup-swift@v2` in GitHub Actions. This repository uses `vapor/swiftly-action`; keep the preceding Ubuntu package-index refresh when changing that setup.
- Shared agent skills live in `.agents/skills/`. `.claude/skills` is a symlink to that directory; edit skills there.

## Toolchain

- Use the Swift version recorded in `.swift-version` and the Ruby version recorded in `.ruby-version`.
- Run `npm ci`, not an unpinned global quicktype install. `package-lock.json` is the generator dependency source of truth.
- Development tools live in the nested `Tools` package, not the root manifest: `swift-openapi-generator` for code generation, and the SwiftFormat binary target and command plugin behind `make format`. Nothing depends on `Tools`, so `Tools/Package.swift` pins the generator with `exact:` and `Tools/Package.resolved` is committed; the root `Package.resolved` is not.
- Do not add tool-only dependencies or binary targets to the root manifest. SwiftPM downloads a dependency package's binary targets for every client. `swift-docc-plugin` stays in the root because `make doc` documents the root package's products and clients do not fetch it.
- When bumping the generator, update `Tools/Package.swift`, run `swift package --package-path Tools update`, then regenerate and commit the lockfile with any generated drift. Keep the root `swift-openapi-runtime` lower bound at or above what that generator version requires.

## Module Ownership

- Slack Events payload types are app-level runtime models owned by `SlackApp` (`Sources/SlackApp/Events`), not `SlackClient`. Their decoding tests belong in `Tests/SlackAppTests`.
- Files directly under `Sources/SlackModels` are hand-written models; `Sources/SlackModels/Generated` is generator-owned.

## Code Generation

- The generator owns `Sources/SlackClient/WebAPI/Generated`, `Sources/SlackApp/Events/Generated`, and `Sources/SlackModels/Generated`. Change the source specs or scripts and regenerate instead of hand-editing generated files.
- `scripts/process_webapi.rb` also updates the generated Web API trait list in `Package.swift`; include that manifest change when regeneration produces one.
- `make generate` deletes all three generated trees before rebuilding them. Review additions, modifications, and deletions; stale files removed upstream should also disappear downstream.
- Treat quicktype or OpenAPI generator failures as fatal. Do not keep partially written output or bypass a failed command.
- When inferred types conflict, inspect both Java SDK samples under `vendor/java-slack-sdk/json-logs/samples` and the corresponding Slack reference schema under `vendor/slack-api-ref`. Samples show observed payloads; the reference may contain broader or more authoritative constraints.
- `make update` advances the vendor submodules to their upstream branches and changes the recorded gitlinks. Use it only when an upstream schema update is in scope.
- `make clean` is destructive: it removes generated directories, resets and cleans both vendor submodules, and restores their recorded commits. Do not run it merely to clear build artifacts or when a vendor checkout contains work that must be preserved.
- `GENERATION_JOBS=<n>` can reduce Ruby generator concurrency on constrained machines. Do not commit machine-specific values.

### Web API Coverage

- A Web API method is generated only when java-slack-sdk has a response fixture for it (`vendor/java-slack-sdk/json-logs/samples/api/<method>.json`). slack-api-ref supplies the method list and request arguments, not response types; do not generate response types from its documentation examples.
- `UNSUPPORTED_METHODS` in `scripts/generate_webapi.rb` excludes legacy methods. Anchor every pattern to the start of the method name and give each entry an inline reason.

### Hand-written Models

When an inferred response type is wrong or badly named, replace it with a hand-written model instead of editing generated output:

1. Add the Swift type as `Sources/SlackModels/<Name>.swift`, following the java-slack-sdk model's name and fields where one exists.
2. Keep the file basename equal to the Swift type name. The extractor and Web API transformer discover handwritten models directly from `Sources/SlackModels/*.swift`; no separate type registry is needed. Files under `Generated` do not count as handwritten overrides.
3. Add a ref-fixer visitor in `scripts/lib/visitors.rb` that points the affected properties at `#/components/schemas/<Name>` and leaves an empty placeholder schema for it, following `UserProfileRefFixer` and `TeamProfileRefFixer`. Register it in the `visitors` list in `generate_openapi_component` in `scripts/generate_webapi.rb`.
4. Generated code then references `SlackModels.<Name>`, because `scripts/process_webapi.rb` maps any schema that has a file in `Sources/SlackModels`.

Nested schema names such as `Call` or `Icons` are shared across all methods, and the last definition merged wins. When a new method's response looks wrong, check whether another fixture defines the same name with a different shape.

## Serialization

- Map snake_case keys with explicit `CodingKeys`, in generated and hand-written types alike. Do not switch to key encoding or decoding strategies.
- Keep the `_type` property name that the generator produces; event types depend on it.

## Verification

- For handwritten Swift changes, run `swift test`. A focused `swift build` is sufficient only when the task cannot affect behavior.
- For schema or generator changes, run `npm ci`, a full `make generate`, and `swift test`. Confirm regeneration leaves no unexplained generated drift.
- When changing Ruby generation helpers or other scripts, run `make test-scripts` in addition to the full generation pass.
- For formatting-only changes, run `make format` and at least `swift build`; use `swift test` when formatting accompanies behavioral changes.

## Release Workflow

- Releases use calendar versions in the form `YYYY.M.PATCH`, such as `2026.7.0`.
- `PATCH` is the release counter within a month, not a SemVer compatibility signal. Start at `0` each month and increment it for additional releases that month.
- Release tags never use a `v` prefix.
- Prepare release metadata on a branch, rename the `[Unreleased]` `CHANGELOG.md` section to the dated release section, and merge it through a PR. Release notes come from that exact changelog section; use bare PR references such as `#123`.
- Publish only after the preparation PR is merged and local `main` is clean and exactly matches `origin/main`.
- `ruby scripts/release.rb YYYY.M.PATCH --yes` is a publication command: it builds, tests, creates and pushes the annotated tag, and creates a draft GitHub release with the version's `CHANGELOG.md` section as its notes. Publishing the draft is a separate step. Never run it from a topic branch or as part of release preparation.
