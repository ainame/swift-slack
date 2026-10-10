# AGENTS.md

Shared guidance for coding agents working in this repository, a Swift Slack SDK and app framework: generated Web API and model layers plus a handwritten runtime for interactive Slack apps over Socket Mode or signed HTTP requests. This file holds the rules and constraints the code does not show; read the code, `Package.swift`, the `Makefile`, and the README for everything else.

## Repository Conventions

- Do not push directly to `main`; use branches and PRs.
- Inspect `git status` before editing or staging. Preserve unrelated user changes and stage only files that belong to the current task.
- Make a focused git commit for each meaningful change.
- Prefer changing the owning source, generator, or handwritten runtime layer instead of patching downstream symptoms.
- Keep PR descriptions and verification notes free of user-specific absolute paths or local environment details.
- When discussing models or fields, explicitly name the repository: upstream `java-slack-sdk` models/fixtures, upstream `slack-api-ref` schemas/definitions, or downstream `swift-slack` generated/handwritten models. Attribute additions, changes, omissions, dates, and snapshots to that repository so their origin is clear.
- PRs with notable changes for library consumers or contributors update `## [Unreleased]` in `CHANGELOG.md`; significant contributor improvements go in `Maintenance`, and routine housekeeping needs no entry. Use `.agents/skills/update-changelog/SKILL.md` to review and consolidate the complete PR’s entries after follow-up commits. Mark breaking changes with `**BREAKING**:` and end each bullet with its PR reference, such as `- #123`; open the PR first to get its number.
- Do not use `swift-actions/setup-swift@v2` in GitHub Actions. This repository uses `vapor/swiftly-action`; keep the preceding Ubuntu package-index refresh when changing that setup.
- Shared agent skills live in `.agents/skills/`. `.claude/skills` is a symlink to that directory; edit skills there.

## Toolchain

- Use the Swift version recorded in `.swift-version` and the Ruby version recorded in `.ruby-version`.
- The generator parses upstream java-slack-sdk sources with tree-sitter through the `ruby_tree_sitter` gem. `make tree-sitter-java` compiles the grammar from the pinned `vendor/tree-sitter-java` submodule with the system C compiler; `make generate`, `make test-scripts` and `make check-fixtures` build it on demand. `make update` deliberately leaves that submodule pinned; bump it only when upstream Java syntax requires it.
- Run `bundle install` for the Ruby scripts, which the `Makefile` and `scripts/generate_all.sh` run through `bundle exec`. `Gemfile.lock` pins json 2.19.1 or later because Ruby 4.0.7's bundled json 2.18.0 has generator GC bugs that intermittently fail `to_json` on Linux.
- Development tools live in the nested `Tools` package, not the root manifest: `swift-openapi-generator` for code generation, and the SwiftFormat binary target and command plugin behind `make format`. Nothing depends on `Tools`, so `Tools/Package.swift` pins the generator with `exact:` and `Tools/Package.resolved` is committed; the root `Package.resolved` is not.
- Do not add tool-only dependencies or binary targets to the root manifest. SwiftPM downloads a dependency package's binary targets for every client. `swift-docc-plugin` stays in the root because `make doc` documents the root package's products and clients do not fetch it.
- When bumping the generator, update `Tools/Package.swift`, run `swift package --package-path Tools update`, then regenerate and commit the lockfile with any generated drift. Keep the root `swift-openapi-runtime` lower bound at or above what that generator version requires.

## Module Ownership

- Slack Events payload types are app-level runtime models owned by `SlackApp` (`Sources/SlackApp/Events`), not `SlackClient`. Their decoding tests belong in `Tests/SlackAppTests`.
- Shared Web API and event models are generated into `SlackClient` as `Components.Schemas.<Name>` with a top-level typealias (`User`, `Message`, ...). Event types are generated into `SlackApp` as extensions of `Components.Schemas`.
- Interaction payload types (`Sources/SlackApp/Requests/Interactions/Payloads`) are hand-written and not generated.

## Code Generation

- The generator owns `Sources/SlackClient/WebAPI/Generated`, `Sources/SlackApp/Events/Generated`, and `Tests/SlackClientTests/Generated`. Change the source specs or scripts and regenerate instead of hand-editing generated files.
- `make generate` (`scripts/generate_all.sh`) runs three steps. `scripts/generate_webapi.rb` writes `.tmp/WebAPI/openapi.json`: paths and request bodies from upstream slack-api-ref, response and event schemas from the upstream java-slack-sdk Java classes (`scripts/lib/java_openapi`). Apple's swift-openapi-generator turns it into Swift, and `scripts/process_webapi.rb` splits that into the source tree and updates the Web API trait list in `Package.swift`; include that manifest change when regeneration produces one.
- `make generate` deletes the generated trees before rebuilding them. Review additions, modifications, and deletions; stale files removed upstream should also disappear downstream.
- Treat generator failures as fatal. Do not keep partially written output or bypass a failed command. The Java translator raises on syntax errors, unmodelled Java constructs, unresolved type names, Gson adapters without a decision, stale or unused overrides and hand-written schemas, and shared model names that clash with existing top-level types.
- `make update` advances the java-slack-sdk and slack-api-ref submodules to their upstream branches and changes the recorded gitlinks. Use it only when an upstream schema update is in scope.
- `make clean` is destructive: it removes generated directories, resets and cleans both vendor submodules, and restores their recorded commits. Do not run it merely to clear build artifacts or when a vendor checkout contains work that must be preserved.

### Java-derived Types

- Each `<Method>Response` class under `com.slack.api.methods.response` is a method's response; `JavaOpenAPI::RESPONSE_CLASSES` maps the few that do not follow that name. Event classes under `com.slack.api.model.event` are events, dispatched by their `TYPE_NAME` and `SUBTYPE_NAME` constants.
- Top-level model classes become shared schemas; Java inner classes become nested types that swift-openapi-generator names `<Property>Payload` (`...PayloadPayload` for array elements).
- Every property is optional except `ok` of a response and `type` of an event. JSON keys follow Gson: `@SerializedName`, otherwise snake_case of the field name.
- Block Kit classes map onto the hand-written SlackBlockKit types through swift-openapi-generator `typeOverrides`.
- Types that upstream reads through a registered Gson type adapter need an explicit decision in `scripts/lib/java_openapi/gson_adapters.rb`.

### Exceptions to the Java Declarations

Keep exceptions explicit, one per field or type, and backed by upstream java-slack-sdk fixtures:

- `scripts/java_type_overrides.yml` replaces the type of one Java field when recorded fixture values contradict it (typically Gson coercing a JSON number into a Java `String`), or adds a field (`added: true`) that recorded responses carry but the Java class does not declare. The generated property gets a `///` comment saying so. Mismatches seen only in slack-api-ref documentation examples do not justify an entry.
- `scripts/handwritten_schemas.yml` holds OpenAPI schemas for shapes that a Java declaration cannot describe, such as Gson adapter types with several JSON shapes. Use `oneOf` with `x-swift-accessors` for read access and `x-java-class` to reuse a Java class. Do not hand-write Swift for Web API or event models.
- Fixture preprocessing in `scripts/lib/java_openapi/fixture_placeholders.rb` only removes the recorder's placeholders for the decode check. Never change library types to tolerate fixture placeholders.

### Web API Coverage

- A Web API method is generated only when java-slack-sdk has a response fixture for it (`vendor/java-slack-sdk/json-logs/samples/api/<method>.json`), and an event only when it has an event fixture. slack-api-ref supplies the method list and request arguments, not response types; do not generate response types from its documentation examples.
- `UNSUPPORTED_METHODS` and `UNSUPPORTED_EVENTS` in `scripts/generate_webapi.rb` exclude legacy methods and events. Anchor every pattern to the start of the name and give each entry an inline reason.

## Serialization

- Map snake_case keys with explicit `CodingKeys`, in generated and hand-written types alike. Do not switch to key encoding or decoding strategies.
- Keep the `_type` property name that the generator produces; `SlackEvent` depends on it.

## Verification

- For handwritten Swift changes, run `swift test`. A focused `swift build` is sufficient only when the task cannot affect behavior.
- For schema or generator changes, run `bundle install`, a full `make generate`, `make check-fixtures`, and `swift test`. Confirm regeneration leaves no unexplained generated drift.
- When changing Ruby generation helpers or other scripts, run `make test-scripts` in addition to the full generation pass.
- For formatting-only changes, run `make format` and at least `swift build`; use `swift test` when formatting accompanies behavioral changes.

## Release Workflow

- Releases use calendar versions in the form `YYYY.M.PATCH`, such as `2026.7.0`.
- `PATCH` is the release counter within a month, not a SemVer compatibility signal. Start at `0` each month and increment it for additional releases that month.
- Release tags never use a `v` prefix.
- Prepare release metadata on a branch, rename the `[Unreleased]` `CHANGELOG.md` section to the dated release section, and merge it through a PR. Release notes come from that exact changelog section; use bare PR references such as `#123`.
- Publish only after the preparation PR is merged and local `main` is clean and exactly matches `origin/main`.
- `ruby scripts/release.rb YYYY.M.PATCH --yes` is a publication command: it builds, tests, creates and pushes the annotated tag, and creates a draft GitHub release with the version's `CHANGELOG.md` section as its notes. Publishing the draft is a separate step. Never run it from a topic branch or as part of release preparation.
