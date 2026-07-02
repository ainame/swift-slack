# AGENTS.md

Shared guidance for coding agents working in this repository.

## Repository Conventions

- Make git commits for each meaningful change.
- Use calendar versioning for releases in the form `YYYY.M.PATCH` (for example `2026.7.0`).
- Treat `PATCH` as the release counter within the month, not as a SemVer compatibility signal.
- Reset `PATCH` to `0` for the first release in each month, then increment it for additional releases in that month.
- Create release tags without a `v` prefix (for example `2026.7.0`).
- Do not use `swift-actions/setup-swift@v2` in GitHub Actions.
- Run `swift build` or `swift test` when verification is needed.
- Do not push directly to `main`; use branches and PRs.

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
make update    # Update git submodules (vendor/*)
make generate  # Run full code generation
make clean     # Clean temp files
```

### Pipeline

1. Ruby scripts transform Slack API specs into OpenAPI JSON.
2. `swift-openapi-generator` produces Swift client and type definitions.
3. `scripts/process_webapi.rb` splits generated Web API output and extracts shared models.
4. `scripts/process_events.rb` extracts generated event types and related conformances into `Sources/SlackApp/Events/Generated`.
5. SwiftFormat applies formatting (4-space indentation).

When changing generated surfaces, prefer updating the source specs/scripts and rerunning generation instead of hand-editing generated files.

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
- Helpful filtered build output command:

```bash
swift build 2>&1 | awk '/error:|warning:|fatal error:/{flag=1} flag && /^$/{flag=0} flag'
```

## Useful Commands

```bash
# Development
make update
make generate
swift build
swift test
make format

# Examples
cd DemoApps/Examples && swift run chatPostMessage
cd DemoApps/Examples && swift run router
cd DemoApps/Examples && swift run echoSlashCommand
cd DemoApps/deepl-translator && swift run

# Release
ruby scripts/release.rb [version] [--yes]
```
