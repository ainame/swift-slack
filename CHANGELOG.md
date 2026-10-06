# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project uses calendar versioning in the form `YYYY.M.PATCH`.
The `PATCH` segment is a release counter within the month, not a SemVer compatibility signal.
An optional `Maintenance` section records notable contributor improvements as a project-specific extension.

## [Unreleased]

### Added

* Added `Router.onAction(_:blockId:handler:)`, which matches the interacted element's `action_id`, and its `block_id` when given, like Bolt's `app.action(...)`. Unlike `onBlockAction`, it handles elements in messages as well as in modals and App Home - #155
* Added `BlockActionsPayload.blockActions`, following java-slack-sdk's `BlockActionPayload.Action`, with each action's `actionId`, `blockId`, `actionTs`, and selected values such as `value`, `selectedOption`, `selectedOptions`, `selectedUser`, `selectedDate`, `selectedDateTime`, and `richTextValue`, and `BlockActionsPayload.containsAction(_:blockId:)` - #155
* Added optional `recordChannel`, `codeChannel`, and `agentSession` fields to swift-slack's conversation `Properties`, with `RecordChannel`, `CodeChannel`, and `AgentSession` models matching java-slack-sdk payloads - #149

### Changed

* Rewrote the README around a runnable Socket Mode bot and an end-to-end `/echo` quick start, and reorganized the DocC catalogs: a `SlackClient` Getting Started that reads Web API responses, the Block Kit example gallery moved to `SlackBlockKitDSL`, a single migration guide in the `SlackApp` documentation, and `SlackKit` added to the Swift Package Index documentation targets - #150
* **BREAKING**: Changed `ContextElementBuilder`, `OptionGroupBuilder`, `RichTextElementBuilder`, `RichTextSectionBuilder`, `RichTextContentBuilder`, and `MarkdownBuilder` to build arrays from each expression. Custom `buildExpression` overloads added to these builders must now return an array, such as `[ContextElementType]` or `[String]`, and direct calls to their `build*` methods must pass and expect arrays - #151

### Deprecated

* Deprecated `Router.onBlockAction(_:handler:)`, which was implemented incorrectly: it does not match Bolt's `app.action(...)`, which matches the element's `action_id`, and matches the containing view's `callback_id` instead, so it never matches elements in messages. Use `onAction(_:blockId:handler:)` for each element, or `onInteractive(_:)` with `payload.callbackId` for a whole view. It will be removed in a 2027 release - #155
* Deprecated `BlockActionsPayload.actions`, which returns Block Kit element definitions without `block_id` or selected values, in favor of `blockActions`. It will be removed in a 2027 release - #155
* Deprecated the public type `BlockActionsPaylaod`, which misspelled "Payload", and renamed it to `BlockActionsPayload`. The old name remains as a typealias with a fix-it and will be removed in a 2027 release - #155

### Fixed

* Fixed `block_actions` requests that failed to decode, so no handler ran, when the action came from checkboxes, radio buttons, overflow menus, or multi-static selects, which Slack sends without the element's `options`, or from element types swift-slack did not model, such as dispatch-enabled text inputs. The deprecated `actions` now skips those elements - #155
* Fixed Socket Mode leaving interactive requests and slash commands unacknowledged when no handler matched, which made Slack show the user an error; they now receive an empty acknowledgement, as in HTTP mode - #155
* Fixed Socket Mode closing the connection and making `SlackApp.run()` throw when one message failed to decode, such as a message event containing a block type swift-slack does not model. The error is now logged and the app keeps reading messages, as in HTTP mode. Events API envelopes that fail to decode are acknowledged so Slack does not retry them; interactive requests and slash commands are not, so Slack shows the user an error instead of, for example, closing a submitted modal - #159
* Fixed swift-slack conversation response decoding that silently discarded `at_here_restricted`, `at_channel_restricted`, and `channel_workflows` from java-slack-sdk fixtures; exposed them as `atHereRestricted`, `atChannelRestricted`, and `channelWorkflows`, with the `ChannelWorkflow` model - #149
* Fixed README and DocC examples that did not compile against the current API, covering `TextObject(type:text:)` and other initializer argument orders, `Text.type(_:)`, `Modal(title:)`, `OptionGroup(label:)`, `context.say(text:channel:)`, `context.respond(to:)`, and missing imports; handler examples now call the Web API through `context.client`, and modal examples set the block IDs their submission handlers read - #150
* Fixed DocC guides that listed 18 of the 33 `WebAPI_*` traits, pinned installation to 0.5.1, and misattributed swift-slack's upstream sources; the Traits guide now lists every trait and explains default and `.defaults` trait selection - #150
* Fixed `SlackBlockKitDSL` so control flow (`if`, `if let`, `if/else`, `switch`, and `for`) compiles inside `Context`, `RichText`, `RichList`, `RichSection`, `RichQuote`, `RichPreformatted`, and `StaticSelect` option groups - #151
* Fixed `Markdown { ... }` emitting a blank line for an `if` whose condition was false or a `for` loop with no iterations - #151

### Maintenance

* Moved CI to `ubuntu-26.04` ahead of the `ubuntu-latest` migration, installed the `.swift-version` toolchain through swiftly instead of using the runner image's preinstalled Swift, and keyed Swift build caches by runner image - #162
* Simplified swift-slack handwritten model overrides by discovering source files and sharing extraction logic - #149
* Moved scheduled upstream schema review to the `slack-upstream-sync` Codex skill, covering generated and handwritten models, and retained Schema Update as a manual Actions fallback - #148
* Removed `CLAUDE.md` and moved agent skills from `.codex/skills` to `.agents/skills`, so Claude Code and Codex share `AGENTS.md` and one skills directory, with `.claude/skills` linking to it - #147
* Required PRs to add their changes to the `Unreleased` section of `CHANGELOG.md` - #147
* Trimmed `AGENTS.md` to the rules and constraints agents cannot learn from the code, removing module, layout, trait, runtime, and command listings that duplicated the repository - #147
* Made `scripts/release.rb` use the version's `CHANGELOG.md` section as the draft release notes instead of merged PR titles, and stop before tagging when that section is missing - #147

## [2026.10.1] - 2026-10-01

This is a follow-up to 2026.10.0, which stopped tracking `Package.resolved`. It moves development-only tools out of the root package manifest, so resolving swift-slack no longer pulls them into client dependency graphs.

### Changed

* Moved swift-openapi-generator out of the package manifest into a nested `Tools` package that pins it at 1.11.0 with a committed `Package.resolved`, so `make generate` reproduces the checked-in code now that the root lockfile is untracked - #143
* Moved the SwiftFormat binary target and formatting plugin into the `Tools` package, so clients no longer download the SwiftFormat artifact bundle when resolving swift-slack - #143

## [2026.10.0] - 2026-10-01

> [!IMPORTANT]
> **The `usergroups.*`, `admin.usergroups.*`, and `admin.workflows.*` Web API operations have been missing from every release since the initial 0.0.1.** The generator's exclusion list used unanchored patterns, so `/groups\./`, meant for the legacy `groups.*` API, also matched `usergroups.*` and `admin.usergroups.*`, and `/workflows\./` also matched `admin.workflows.*` and `functions.workflows.*`. This release fixes the patterns. The affected methods that have a java-slack-sdk fixture are generated for the first time, with the `WebAPI_Usergroups` trait: all 7 `usergroups.*`, 4 of 5 `admin.usergroups.*`, and 5 of 7 `admin.workflows.*` operations. The others, including `functions.workflows.*`, have no fixture yet - #140

> [!WARNING]
> **If you adopted 2026.9.0 or 2026.9.1, this release removes 17 Web API operations you may be using.** Those releases shipped operations for methods that java-slack-sdk has no response fixture for. Their response types were either reduced to `ok` only (#121) or inferred from slack-api-ref documentation examples (#135), not from real responses. Shipping them was a mistake. From this release, Web API coverage is aligned with the official [java-slack-sdk](https://github.com/slackapi/java-slack-sdk): a method is generated only when that SDK supports it with a recorded response. The removed operations are listed under Changed below. If you call any of them, stay on 2026.9.1 or call the Slack method with your own HTTP request until they return.

### Added

* Added generated `calls.*`, `workflows.featured.*`, and `api.test` Web API operations, which were previously excluded on purpose but are current APIs, with new `WebAPI_Calls`, `WebAPI_Workflows`, and `WebAPI_Api` traits - #140
* Added hand-written `Call`, `CallParticipant`, `APITestArgs`, `AppWorkflow`, `AppIcons`, and `WorkflowCollaboratorError` models, following java-slack-sdk, for `calls.*`, `api.test`, `admin.workflows.search`, and `admin.workflows.collaborators.*` responses - #140
* Reported Web API methods skipped during generation as warnings, aggregated into one GitHub Actions annotation and the job summary - #140

### Changed

* Updated the development Swift toolchain to `6.4.0` and stopped tracking `Package.resolved` so development resolves dependencies from the package manifest - #141
* **BREAKING**: Removed 17 Web API operations that 2026.9.0 and 2026.9.1 shipped by mistake without a java-slack-sdk response fixture. Operations are now generated only for methods with a fixture, and these return once java-slack-sdk adds fixtures for them - #140
  * `admin.apps.mcp.servers.list`
  * `admin.apps.mcp.servers.permissions.list`
  * `admin.apps.mcp.servers.permissions.set`
  * `admin.apps.permissions.add`
  * `admin.apps.permissions.list`
  * `admin.apps.permissions.remove`
  * `admin.apps.permissions.set`
  * `admin.audit.anomaly.allow.getItem`
  * `admin.audit.anomaly.allow.updateItem`
  * `admin.conversations.bulkSetProperties`
  * `admin.conversations.linkObjects`
  * `admin.conversations.unlinkObjects`
  * `apps.auth.external.delete`
  * `apps.managed.permissions.set`
  * `assistant.search.context`
  * `entity.acknowledgeCommentAction`
  * `entity.presentComments`

### Fixed

* Declared `SlackApp`'s NIO product dependencies explicitly to fix Socket Mode compilation after fresh dependency resolution - #141
* Added the missing `userCount`, `deletedBy`, and `autoType` fields to `Usergroup`, which is now hand-written following java-slack-sdk. Its generated model kept only the fields of one fixture - #140
* Fixed the unanchored Web API exclusion list patterns that dropped the `usergroups.*`, `admin.usergroups.*`, and `admin.workflows.*` operations since 0.0.1, as described above - #140

## [2026.9.1] - 2026-09-27

### Added

* Added container and task-card Block Kit models, URL source elements, Slack icons, and DSL support for nested container blocks - #135

### Changed

* **BREAKING**: Added container and task-card cases to `Block`, requiring updates to exhaustive switches, and removed `isEmbeddedPreviewEnabled` from `admin.apps.config.set` to match the upstream schema - #135
* Updated Slack schemas and streaming API descriptions - #135
* Updated the Ruby toolchain to `4.0.7` - #136

### Fixed

* Restored `admin.apps.permissions.remove` and `admin.apps.permissions.set` generation with channel restriction fields after upstream response examples changed - #135
* Made Web API generation support multiple response samples and reject invalid reviewed examples, and installed locked generator dependencies before CI script tests - #135

## [2026.9.0] - 2026-09-03

### Added

* Added generated Web API operations for methods without response examples, including new Admin, Apps, Assistant, and Entity coverage - #121
* Expanded generated Web API and shared model coverage from the latest Slack schemas - #127, #129
* Added generated Agents and Blocks Web API groups and traits - #133

### Changed

* Made schema generation reproducible with a locked quicktype toolchain, fail-fast processing, bounded concurrency, generated-tree PR gating, and required script tests - #123
* Updated the Ruby toolchain to `4.0.6` and quicktype to v26 - #122, #125, #126
* Updated the GitHub Actions Node setup action to v7 - #124

### Fixed

* Fixed MCP response component naming during Web API schema generation - #128
* Made Web API group discovery use vendored schema metadata and fail generation instead of emitting an unknown group - #131
* Preserved canonical OAuth and OpenID group names so their generated components use active traits - #132

## [2026.7.0] - 2026-07-02

### Added

* Updated Slack API schemas with newly generated Web API operations and shared model coverage - #112, #113, #115, #118

### Changed

* Adopted calendar versioning in the form `YYYY.M.PATCH`, starting with this release - #119
* Updated README package-version examples for the `2026.7.0` release - #119
* Updated the Ruby toolchain reference to `4.0.5` - #111
* Tightened the release workflow guidance to keep tag and GitHub release publication on merged `main` commits and prefer GitHub-native PR references in changelog entries - #119, #120
* Updated GitHub Actions checkout and cache actions - #114, #116
* Updated GitHub Actions Swiftly setup and refreshed the apt index before Swiftly installation - #118

### Fixed

* Fixed generated channel priority property typing - #117
* Fixed Web API trait template generation and indentation - #118
* Removed stale generated schema output from the generation pipeline - #118

## [0.11.0] - 2026-05-19

### Added

* Updated Slack API schemas with newly generated Web API operations for Bookmarks, Chat, Conversations, and OpenID API surfaces - [#110](https://github.com/ainame/swift-slack/pull/110)

### Changed

* Updated the Ruby toolchain reference to `4.0.4` - [#106](https://github.com/ainame/swift-slack/pull/106)
* Updated README package-version examples for the `0.11.0` release.

### Fixed

* Fixed SwiftFormat processing for the generated Web API protocol by preserving formatter-disable directives around `APIProtocol.swift` - [#107](https://github.com/ainame/swift-slack/pull/107), [#108](https://github.com/ainame/swift-slack/pull/108), [#109](https://github.com/ainame/swift-slack/pull/109)

## [0.10.0] - 2026-05-08

### Added

* Updated Slack API schemas with newly generated Web API operations for Admin, Apps, Assistant, and Chat API surfaces - [#102](https://github.com/ainame/swift-slack/pull/102), [#105](https://github.com/ainame/swift-slack/pull/105)
* Expanded generated Slack component and shared model coverage across Admin, Apps, Bots, Conversations, DND, Files, Reactions, Team, Users, and shared model types - [#104](https://github.com/ainame/swift-slack/pull/104)

### Changed

* Cleaned up the DeepL translator demo, including shortcut-flow documentation, default-language handling in the translation modal, and unused code removal - [#99](https://github.com/ainame/swift-slack/pull/99)
* Updated the SwiftFormat binary target to `0.61.0` and refreshed the demo formatting produced by that toolchain - [#100](https://github.com/ainame/swift-slack/pull/100)
* Updated the DocC publishing workflow to `actions/upload-pages-artifact@v5` - [#101](https://github.com/ainame/swift-slack/pull/101)
* Updated the Ruby toolchain reference to `4.0.3` - [#103](https://github.com/ainame/swift-slack/pull/103)
* Updated README package-version examples for the previous release cycle - [#96](https://github.com/ainame/swift-slack/pull/96)

### Fixed

* Fixed Renovate updates for the SwiftFormat binary target by using release-attachment metadata for checksum replacement and removing the post-upgrade checksum script - [#97](https://github.com/ainame/swift-slack/pull/97)
* Fixed Renovate SwiftFormat replacement formatting so version and checksum updates do not capture extra newlines in `Package.swift` - [#98](https://github.com/ainame/swift-slack/pull/98)

## [0.9.0] - 2026-04-01

### Added

* Added explicit support in `HummingbirdAdapter` for Slack interactive requests via `/slack/interactive-endpoint` - #94

### Changed

* **BREAKING**: Replaced the public `HTTPServerRequest` and `HTTPServerResponse` wrapper types with an `HTTPTypes`-based `HTTPServerHandler` API, giving `HTTPServerAdapter` implementations direct access to the incoming `HTTPRequest` and request body - #94
* Simplified the `SlackApp` HTTP runtime and Hummingbird integration, including a plain `/healthz` response, while allowing adapters to handle Slack web requests at whichever request path they choose - #94
* Updated the `DemoApps/deepl-translator` example to switch between Socket Mode and Hummingbird HTTP via traits, add message shortcut replies, and load configuration via `swift-configuration` - #94
* Added Renovate support for the SwiftFormat binary target, including checksum refresh automation for version bumps - #93

## [0.8.0] - 2026-03-31

### Changed

* Moved the standalone examples package under `DemoApps/Examples` and updated local package references and docs to match - #88
* Documented `HTTPServerAdapter` as a supported public extension point and added coverage for custom HTTP server adapters.
* Reorganized the `SlackApp` target so HTTP support lives under `Sources/SlackApp/HTTP/` and Socket Mode support lives under `Sources/SlackApp/SocketMode/`.
* Moved the `Say` and `Respond` runtime helpers from `SlackClient` into `SlackApp`.
* Moved inbound request envelopes and interaction payload types from `SlackClient` into `SlackApp`.
* Moved generated Events API payload types from `SlackClient` into `SlackApp` and updated docs, tests, and generation outputs to match the new module boundary.
* Split DocC content so `SlackClient.docc` stays focused on the Web API client while `SlackApp.docc` owns Socket Mode and runtime-oriented examples.
* Added `.ruby-version` support to the schema update workflow - #91
* Updated Slack API schemas - #92

### Fixed

* Fixed the schema generation helper queue population in `scripts/lib/helpers.rb`.

## [0.7.0] - 2026-03-30

### Changed

* Updated `apple/swift-crypto` to `4.3.0`.
* Preserved SwiftPM dependency ranges in Renovate updates - #85
* Updated the GitHub Pages deployment workflow to `actions/deploy-pages@v5` - #73
* Enabled DocC generation for `SlackApp` so its symbols are included in the published documentation site - #86
* Made the built-in `HummingbirdAdapter` integration opt-in via the `HummingbirdHTTPAdapter` package trait and updated the README to document HTTP setup - #87
* Fixed the DocC publishing script used by the documentation workflow.

## [0.6.0] - 2026-03-29

### Added

* Added a shared app runtime with `SlackApp`, `Router`, transport-neutral `Ack`, `Slack.Configuration`, HTTP request handling, and optional Hummingbird integration.
* Added app runtime coverage for shared router dispatch and HTTP request handling.
* Added migration documentation at `MIGRATING_TO_SLACKAPP.md`.
* Added a new `SlackKit` umbrella product that re-exports `SlackApp`, `SlackClient`, and `SlackBlockKit` for normal app-authoring workflows.

### Changed

* **BREAKING**: Split the app runtime out of `SlackClient` into a new `SlackApp` product.
* Moved Socket Mode, HTTP request handling, routing, acknowledgements, and the existing Hummingbird integration into `SlackApp`.
* Updated examples, README, migration notes, and DocC guides to make `SlackKit` the primary app-authoring entry point while keeping `SlackApp` as the lower-level runtime module.
* Updated `DemoApps/deepl-translator` to use the current `SlackApp` runtime flow and removed obsolete package dependencies.
* Simplified `DemoApps/Examples/Sources/blockActionsMessageContainer` to use `SlackApp` setup via the `preparing` hook and typed Block Kit-based unfurl payload construction.

## [0.5.1] - 2026-03-23

### Added

* Added top-level third-party attribution notices for vendored generation inputs - #68

### Changed

* Renamed the vendored upstream submodule directory from `.dependencies/` to `vendor/` and updated generation scripts and documentation accordingly - #67
* Updated `apple/swift-openapi-generator` to `1.11.0` - #70
* Updated Ruby toolchain references to `4.0.2` - #69

### Fixed

* Fixed form-encoded Web API payload escaping so typed Block Kit requests preserve reserved characters correctly - #71

## [0.5.0] - 2026-03-11

### Added

* Added missing attributes for Slack interaction payloads:
  * `block_actions` now includes function metadata and interactivity fields from Slack's current payload shape.
  * `view_submission` and `view_closed` now include the missing function-related attributes.

### Changed

* Updated Slack API schemas to the latest upstream snapshots - #64, #65
* Updated `apple/swift-openapi-runtime` to `1.11.0` - #62
* Updated `hummingbird-project/swift-websocket` to `1.5.0` - #63

## [0.4.0] - 2026-02-22

### Changed

* Refactored interaction `container` modeling to a typed enum in `SlackModels.Container` - #60

### Fixed

* Fixed `block_actions` decoding for message-container payloads by allowing payloads without `view` - #60

## [0.3.0] - 2026-02-16

### Fixed

* Fixed schema mapping mismatch for user-shaped `profile` fields (issue [#42](https://github.com/ainame/swift-slack/issues/42)).
  * `User.profile`, `Member.profile`, `InvitingUser.profile`, and `TingUser.profile` now map to `UserProfile` instead of `Profile`.
  * Expanded `UserProfile` with missing properties from Slack user profile payloads (status metadata, normalized names, profile fields, additional image sizes, and app/bot metadata).
  * `TeamProfileGetResponse.profile` now maps to `TeamProfile` to reflect `team.profile.get` payload shape (`fields` / `sections`) instead of image-only `Profile`.
  * Updated generation pipeline to apply context-aware profile remapping while keeping `UserProfile` and `TeamProfile` as manually maintained models.

## [0.2.0] - 2025-08-17

### Added

* Minimum DocC documentation support https://ainame.github.io/swift-slack/documentation
* Schema update https://github.com/ainame/swift-slack/pull/33

### Fixed

* Schema update automation issue was resolved https://github.com/ainame/swift-slack/commit/44966ba5be88fe6df115d42f229bd04e9153f472
   * SwiftFormat got bug fixes around trailing commas and that helps us get consistently formatted code in schema updates


## [0.1.2] - 2025-06-28

### 🐛 Fixed
- **Item.ts Property**: Added optional `ts` property to `Item` model for reaction event compatibility
  - Fixed DeepL translator demo app where `item.ts` was accessed but didn't exist
  - `Item` now has `public var ts: Swift.String?` to support both reaction events and other APIs
  - Maintains type safety by keeping `ts` optional since it's not present in all contexts

### ✨ Added
- **Form-Encoding Middleware**: Automatic JSON to form-urlencoded conversion for Slack API compatibility
  - `FormEncodingMiddleware` installed by default in `SlackClient`
  - Transparent handling of Slack's POST + `application/x-www-form-urlencoded` requirement
  - Nested objects automatically serialized as JSON strings in form data
- **swift-dotenv Integration**: Environment variable management for DeepL translator demo
  - Added swift-dotenv dependency for cleaner configuration management
  - Removed ProcessInfo fallbacks in favor of explicit environment variable loading

### 🔧 Enhanced
- **Code Generation Pipeline**: Improved schema generation with `ItemTsOptionalAdder` visitor
  - Automatically adds optional `ts` property to Item schema during generation
  - Ensures consistency across WebAPI and Events API usage
- **Documentation**: Updated README with form-encoding workaround explanation
  - Honest documentation of temporary workaround nature
  - Technical notes section explaining design decisions

### 📋 Technical Notes
- Form-encoding middleware addresses swift-openapi-generator limitation with nested form data
- This is a workaround solution that may be updated in future versions
- All tests passing with new middleware and model changes

## [0.1.1] - 2025-06-28

### 🐛 Fixed
- **Slack API Compatibility**: Resolved `conversations.replies` "invalid_arguments" errors
  - Root cause: Slack APIs expect POST + `application/x-www-form-urlencoded`, not `application/json`
  - swift-openapi-generator doesn't support nested containers with form-urlencoded
- **Modal View Protocol**: Fixed `callbackId` optionality mismatch between protocol and implementation
- **Test Suite**: Disabled WebSocket-dependent test that required mocking infrastructure

### ✨ Added
- **FormEncodingMiddleware**: Automatic request transformation for Slack API compatibility
  - Converts POST + JSON requests to POST + form-urlencoded automatically
  - Handles nested objects by serializing them as JSON strings in form fields
  - Installed by default in SlackClient for transparent operation

### 🔧 Enhanced
- **DeepL Translator Demo**: Improved error handling and API compatibility
  - Fixed reaction event handling with proper `conversations.replies` usage
  - Enhanced duplicate translation detection logic
  - Better fallback handling for non-threaded messages

## [0.1.0] - 2025-06-23

### 🚨 Breaking Changes
- **BREAKING**: Socket Mode interactive handlers now require explicit acknowledgment
  - Removed auto-acknowledgment for interactive handlers (global shortcuts, view submissions, slash commands, block actions, message shortcuts)
  - All interactive handlers must now call `try await context.ack()`
  - Event API handlers remain unchanged (no acknowledgment required)
  - **Migration**: Add `try await context.ack()` at the start of your interactive handlers

### ✨ Added
- **Custom Ack Functionality**: New `Ack` struct with multiple acknowledgment methods
  - `ack()` - Basic acknowledgment
  - `ack(responseAction: .update, view:)` - Update views to keep modals open during processing
  - `ack(errors: [String: String])` - Send validation errors back to forms
  - Support for response actions: `.update`, `.push`, `.clear`
- **StateValuesObject**: New form value extraction system for SlackBlockKit
  - Subscript access: `payload.view.state?["blockId", "actionId"]?.value`
  - Support for `selectedOption`, `selectedOptions`, `selectedDate`, etc.
  - Computed `state` property on `View` enum for easy access
  - Comprehensive unit tests for JSON decoding scenarios
- **DeepL Translator Demo App**: Complete real-world Slack bot implementation
  - Global shortcut and reaction-based translation features
  - Modal UI with form handling and loading states
  - Demonstrates proper custom Ack usage patterns
  - DeepL API integration with shared HTTPClient

### 🐛 Fixed
- Added missing `ts` field to `Item` struct for reaction events
- Fixed reaction event handling for proper `conversations.replies` API usage

### 📚 Documentation
- **Enhanced README**: Comprehensive Socket Mode acknowledgment documentation
- Added practical examples for form validation, loading states, and error handling
- Updated all Socket Mode code examples to demonstrate proper `ack()` usage
- Concrete type examples instead of generic placeholders

### 🔧 Changed
- Updated all examples to use explicit acknowledgment patterns
- Enhanced `SlackModalView` to require non-optional `callbackId`
- Improved error handling patterns throughout Socket Mode handlers

## [0.0.5] - 2025-01-06

### Changed
- **BREAKING**: Renamed `SocketModeMessageRouter` to `SocketModeRouter` for brevity and consistency
  - Class renamed from `SocketModeMessageRouter` to `SocketModeRouter`
  - Method renamed from `addSocketModeMessageRouter(_:)` to `addSocketModeRouter(_:)`
  - All related type references updated accordingly
- Updated Slack API schemas to latest version
- Improved schema update workflow to only detect changes in Generated directories

### Documentation
- Added BlockKit examples section to README
- Fixed various README formatting issues

## [0.0.4] - 2025-06-01

### Added
- **MarkdownBlock Support**: Full implementation of MarkdownBlock with DSL integration and result builder patterns
- **Enhanced RichText API**: Complete coverage of all 9 Slack RichText element types (text, emoji, link, user, channel, date, broadcast, color, usergroup)
- **DSL Convenience Patterns**: Ergonomic initializers and patterns for common input elements and usage scenarios
- **Comprehensive Examples**: New snippet examples demonstrating MarkdownBlock, RichText features, and DSL convenience patterns
- **Shields.io Badges**: Professional badges in README for Swift version, SPM compatibility, license, releases, documentation, and build status

### Enhanced
- **SlackBlockKitDSL**: Added comprehensive convenience initializers for PlainTextInput, StaticSelect, ChannelsSelect, UsersSelect, and other common elements
- **RichText Elements**: Complete implementation of RichTextColorElement and RichTextUsergroupElement with full encoding/decoding support
- **Result Builders**: Enhanced @RichTextElementBuilder and @RichTextContentBuilder to support all element types
- **Code Examples**: Extensive practical examples showing real-world usage patterns across all new features

### Technical
- **Example Organization**: Better organization of code examples with comprehensive DSL and RichText demonstrations

## [0.0.3] - 2025-05-31

### Added
- Comprehensive regression test suite for SocketModeMessageRouter
- Internal initializers for SocketModeMessageEnvelope and EventsApiEnvelope to support testing

### Fixed
- Event type casting issue in SocketModeMessageRouter.onEvent<T: SlackEvent> method
- Generic type parameter handling that was preventing proper event dispatch

### Technical
- Added test coverage for event dispatch mechanism with actual handler execution validation
- Improved testability of SocketMode components

## [0.0.2] - 2025-05-31

### Added
- Comprehensive SlackBlockKit DSL with SwiftUI-like declarative syntax
- Result builders for clean block construction (@BlockBuilder, @ActionElementBuilder, etc.)
- Smart Section handling that automatically converts single Text to text property
- TextObject conformance to ExpressibleByStringLiteral for cleaner syntax
- @autoclosure modifiers for improved DSL ergonomics

### Changed
- **BREAKING**: Renamed core types for better Swift conventions:
  - `ViewType` → `View`
  - `BlockType` → `Block`
  - `EventType` → `Event`
  - `SocketModeMessageType` → `SocketModeMessage`
- Moved Snippets examples to proper Sources directory structure
- Updated Ruby code generation scripts to use new enum names
- Improved CodingKeys handling throughout codebase for proper snake_case conversion

### Fixed
- Compilation errors in Snippets examples by wrapping types in namespace enums
- Redundant @BlockBuilder usage in DSL implementation
- Demo compilation and runtime issues

### Technical
- Enhanced code generation pipeline for better type safety
- Improved separation of concerns between SlackBlockKit and SlackBlockKitDSL modules
- Better error handling and validation in DSL builders

## [0.0.1] - Initial Release

### Added
- Swift Slack client library with auto-generated WebAPI from OpenAPI specs
- Socket Mode support for real-time events
- 141+ shared model types in separate SlackModels module
- Events API with 96+ event types
- Block Kit UI framework implementation
- Comprehensive Ruby-based code generation pipeline
- Conditional compilation support for modular trait selection
- Examples and documentation
