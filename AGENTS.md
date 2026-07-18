# AGENTS.md

Shared guidance for coding agents working in this repository.

## Repository Conventions

- Do not push directly to `main`; use branches and PRs.
- Inspect `git status` before editing or staging. Preserve unrelated user changes and stage only files that belong to the current task.
- Make a focused git commit for each meaningful change.
- Prefer changing the owning source, generator, or handwritten runtime layer instead of patching downstream symptoms.
- Keep PR descriptions and verification notes free of user-specific absolute paths or local environment details.
- Do not use `swift-actions/setup-swift@v2` in GitHub Actions. This repository uses `vapor/swiftly-action`; keep the preceding Ubuntu package-index refresh when changing that setup.

## Toolchain

- Use the Swift version recorded in `.swift-version` and the Ruby version recorded in `.ruby-version`.
- Code generation requires Ruby 3.0+ and Node.js 20+.
- Run `npm ci`, not an unpinned global quicktype install. `package-lock.json` is the generator dependency source of truth.
- Before diagnosing a toolchain failure as a repository bug, check the active `swift`, `ruby`, and `node` executables and versions. On macOS also check the selected `DEVELOPER_DIR`/Xcode SDK if SwiftPM stalls or behaves differently from CI.

## Project Overview

This project is a Swift Slack SDK and app framework. It combines generated Web API and model layers with a handwritten runtime for building interactive Slack apps over Socket Mode or signed HTTP requests.

## Main Modules

- `SlackClient`: Low-level Web API client plus generated API/types and shared client models.
- `SlackApp`: Runtime layer for `SlackApp`, `Router`, inbound request envelopes and interaction payloads, Events API payload types, acknowledgement flow, signed HTTP handling, and Socket Mode execution.
- `SlackKit`: Umbrella product that re-exports the common app-authoring surface for interactive Slack apps.
- `SlackModels`: Shared model module used across the package.
- `SlackBlockKit`: Block Kit framework implementation.
- `SlackBlockKitDSL`: Declarative DSL for building Block Kit payloads.

## Source Layout

- `Sources/SlackClient`: Generated Web API surface plus shared client/model support code.
- `Sources/SlackApp`: Handwritten runtime code for inbound request payloads, event payload types, HTTP adapters, request verification, routing, and Socket Mode.
- `Sources/SlackApp/Events`: Generated Events API payload types owned by `SlackApp`.
- `Sources/SlackKit`: Umbrella exports and top-level documentation for app authors.
- `Sources/SlackModels`: Generated and processed shared Slack model types.
- `Sources/SlackBlockKit`: Block Kit data structures and views.
- `Sources/SlackBlockKitDSL`: Swift DSL for composing Block Kit payloads.
- `Tests/SlackClientTests`, `Tests/SlackAppTests`, `Tests/SlackBlockKitTests`, `Tests/SlackBlockKitDSLTests`: Module-aligned test suites using `swift-testing`.
- Event decoding coverage belongs in `Tests/SlackAppTests` because the event payload types are part of `SlackApp`.
- `DemoApps/Examples/`: Small executable samples wired against the local package.
- `DemoApps/`: Larger end-to-end sample applications.

## Code Generation Workflow

### Commands

```bash
npm ci                # Install the locked quicktype toolchain
make update           # Intentionally advance vendor submodules to their configured upstream branches
make generate         # Clear and regenerate every owned generated Swift tree
make format-generated # Format only generated output
```

`make update` changes vendor gitlinks and is not a routine prerequisite when the checked-out submodules already match the recorded commits. Use it only when an upstream schema update is in scope.

`make clean` is destructive: it removes generated directories, resets and cleans both vendor submodules, and restores their recorded commits. Do not run it merely to clear build artifacts or when a vendor checkout contains work that must be preserved.

### Pipeline

1. The locked quicktype dependency and Ruby scripts transform Slack API specs into OpenAPI JSON.
2. `swift-openapi-generator` produces Swift client and type definitions.
3. `scripts/process_webapi.rb` splits generated Web API output and extracts shared models.
4. `scripts/process_events.rb` extracts generated event types and related conformances into `Sources/SlackApp/Events/Generated`.
5. SwiftFormat formats only the generated directories (4-space indentation).

When changing generated surfaces, prefer updating the source specs/scripts and rerunning generation instead of hand-editing generated files.

### Generated Output Rules

- The generator owns `Sources/SlackClient/WebAPI/Generated`, `Sources/SlackApp/Events/Generated`, and `Sources/SlackModels/Generated`.
- `scripts/process_webapi.rb` also updates the generated Web API trait list in `Package.swift`; include that manifest change when regeneration produces one.
- `make generate` deletes all three generated trees before rebuilding them. Review additions, modifications, and deletions; stale files removed upstream should also disappear downstream.
- Treat quicktype or OpenAPI generator failures as fatal. Do not keep partially written output or bypass a failed command.
- When inferred types conflict, inspect both Java SDK samples under `vendor/java-slack-sdk/json-logs/samples` and the corresponding Slack reference schema under `vendor/slack-api-ref`. Samples show observed payloads; the reference may contain broader or more authoritative constraints.
- `GENERATION_JOBS=<n>` can reduce Ruby generator concurrency on constrained machines. Do not commit machine-specific values.

### Key Scripts

- `scripts/generate_webapi.rb`
- `scripts/generate_events.rb`
- `scripts/process_webapi.rb`
- `scripts/process_events.rb`

## Package Traits and Flags

### Traits

```swift
.package(url: "...", traits: [
    "SocketMode",
    "Events",
    "HummingbirdHTTPAdapter",
    "WebAPI_Chat",
    "WebAPI_Views",
])
```

### Conditional Compilation

- `#if WebAPI_*`: API method availability
- `#if SocketMode`: Socket Mode runtime and `apps.connections.open`
- `#if Events`: Event handling
- `#if HummingbirdHTTPAdapter`: Hummingbird-based HTTP adapter support

## Runtime Notes

- Prefer `SlackClient` when the task is purely about direct Web API access.
- Prefer `SlackKit` for normal interactive app code; it is the intended import surface for most apps.
- `SlackApp` owns routing, inbound request envelopes and payloads, Events API payload types, acknowledgement semantics, request verification, and runtime startup.
- Treat Slack Events payload types as app-level runtime models that belong in `SlackApp`, not `SlackClient`.
- For Socket Mode apps, the usual entry point is `SlackApp(..., mode: .socketMode())`.
- For HTTP apps, use `SlackApp(..., mode: .http(adapter))` with an adapter such as `HummingbirdAdapter`.

## DSL and Events Notes

- `TextObject` supports string literals.
- Section DSL maps a single text child to `text`, multiple to `fields`.
- Keep `_type` naming as-is for event compatibility.
- Message events depend on `subtype` differentiation.
- `onSlackMessageMatched(...)` no longer exists; use `router.onEvent(MessageEvent.self)` and filter inside the handler when needed.
- Events API handlers are auto-acked; slash commands, block actions, shortcuts, and view handlers still need explicit `ack()`.

## Serialization and Naming Rules

- Keep explicit `CodingKeys` for snake_case and camelCase mapping.
- Do not rely on key encoding/decoding strategies as a substitute.
- Keep `SlackView` using `blocks` (not `body`).

## Testing Guidance

- Use `swift-testing` (not XCTest).
- Group tests in suite structs per file.
- Put tests beside the owning module. Event decoding coverage belongs in `Tests/SlackAppTests`; Web API/model mapping coverage belongs in `Tests/SlackClientTests`.
- For handwritten Swift changes, run `swift test`. A focused `swift build` is sufficient only when the task cannot affect behavior.
- For schema or generator changes, run `npm ci`, a full `make generate`, and `swift test`. Confirm regeneration leaves no unexplained generated drift.
- When changing Ruby generation helpers, run `ruby scripts/tests/helpers_test.rb` in addition to the full generation pass.
- When changing release logic, run `ruby scripts/tests/release_test.rb` and review every command that can create or push a tag or release.
- For formatting-only changes, run `make format` and at least `swift build`; use `swift test` when formatting accompanies behavioral changes.
- Helpful filtered build output command:

```bash
swift build 2>&1 | awk '/error:|warning:|fatal error:/{flag=1} flag && /^$/{flag=0} flag'
```

## Release Workflow

- Releases use calendar versions in the form `YYYY.M.PATCH`, such as `2026.7.0`.
- `PATCH` is the release counter within a month, not a SemVer compatibility signal. Start at `0` each month and increment it for additional releases that month.
- Release tags never use a `v` prefix.
- Prepare release metadata and the dated `CHANGELOG.md` section on a branch and merge it through a PR. Release notes come from that exact changelog section; use bare PR references such as `#123`.
- Publish only after the preparation PR is merged and local `main` is clean and exactly matches `origin/main`.
- `ruby scripts/release.rb YYYY.M.PATCH --yes` is a publication command: it builds, tests, creates and pushes the annotated tag, and creates the GitHub release. Never run it from a topic branch or as part of release preparation.

## Useful Commands

```bash
# Swift development
swift build
swift test
make format

# Vendor/schema refresh
npm ci
make update
make generate

# Examples
cd DemoApps/Examples && swift run chatPostMessage
cd DemoApps/Examples && swift run router
cd DemoApps/Examples && swift run echoSlashCommand
cd DemoApps/deepl-translator && swift run

# Publish after the release-preparation PR is merged and main is synchronized
ruby scripts/release.rb [version] [--yes]
```
