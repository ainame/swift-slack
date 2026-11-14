# Upstream snapshots and review coverage

The submodule gitlinks are the generation inputs. Review coverage applies to the
selected delta, not complete historical parity or live Slack service behavior.

## Review on 2026-11-14

Sync PR: #282.

| Source | Previous commit | Reviewed snapshot |
| --- | --- | --- |
| [java-slack-sdk](https://github.com/slackapi/java-slack-sdk) | `383dd5f35085b700db5c926add4705a8e8df56ee` | `66ca90f086bf775f37d6c4ac19a5c34efce5eba6` |
| [slack-api-ref](https://github.com/slack-ruby/slack-api-ref) | `9d12de7552102bcacb8cb72162063a39b7b6d9b9` | `cd2b031eb6ce9db1f04fa9e286985208423b4650` |

Both snapshots are fast-forwards from the pins at
`release-2027-01` commit `0ce30ea942b418e71f2da416c0170b41006fa5c8`.

### Implemented

- Added 15 swift-slack Web API operations with both slack-api-ref request definitions
  and java-slack-sdk response fixtures. These cover seven `slackbot.skills.*`, four
  `admin.slackbot.skills.*`, three `admin.apps.mcp.servers.*` and
  `canvases.getContent`. The downloaded canvas content is a string. The Java
  shared Skill model and admin-list skill payload have separate Swift types.
- Used detailed slack-api-ref request definitions for typed skill and admin MCP
  arrays, including the required service type and optional IDs and Salesforce
  permission namespace on skill MCP server entries. Added request fields
  `canvases.create.channel_id`, `team.info.include_slackbot_availability` and
  `slackLists.download.get.include_archived`. Regenerated changed request comments.
  Fixed form encoding to distinguish numeric 0 and 1 from JSON booleans, so
  `slackbot.skills.list` can send `limit=1`. Matched java-slack-sdk form
  encoding for the new admin ID arrays (comma-separated) and skill MCP server
  objects (JSON arrays).
- The slack-api-ref snapshot removed `agents.conversations.setView.pr_url`.
  Removed the generated property, the handwritten `CodeChannel.View.pullRequest`
  case and its Codex demo tool option. The Java request retains the argument.
  Removed `CodeChannel.CSP.connectDomains` to match the detailed slack-api-ref
  schema. The generated `csp` argument remains an untyped object.
- Matched updated java-slack-sdk declarations for `Conversation.is_file`,
  `Team.slackbot_availability` and `AppManifest.features.user_connections`.
  Applied Gson's new decode aliases for Slack Lists link fields to both standalone
  and attachment-embedded Swift records. Canonical encoding remains snake_case.
- Added handwritten swift-slack `PlanBlock`, `Block.plan`, button prompt and
  visibility fields and their DSL support. Plan tasks omit `type` as shown in the
  upstream Java test and [Slack reference](https://docs.slack.dev/reference/block-kit/blocks/plan-block/).
  Existing standalone task card encoding still includes `type`.
- Generated `UserConnectionEvent` and `UserConnectionStatusRequestedEvent` from
  java-slack-sdk classes, using verbatim connect and status-request test payloads.
  Added a dispatch test for the Java disconnect example. Both connect and disconnect
  use the same event case, with optional `trigger_id` and `enterprise_id` matching
  [Slack's event examples](https://docs.slack.dev/reference/events/user_connection/)
  and the [Node Slack SDK types](https://github.com/slackapi/node-slack-sdk/blob/main/packages/types/src/events/user.ts).
  Swift's event decoder uses the existing generated route for each event type.
- Exhaustive switches over swift-slack `Block` and `Event` require the new cases.
  The pull-request Code channel view removal also changes public source API.

### Reviewed exclusions and coverage gaps

- `admin.analytics.slackbot.skills`, `admin.analytics.slackbot.tools`,
  `admin.conversations.kick`, `admin.users.access.pause`,
  `admin.users.access.resume` and `admin.users.deactivate` lack java-slack-sdk
  response fixtures. The existing seven `admin.usergroups.*` fixture gaps remain.
- java-slack-sdk has response fixtures for `apps.user.connection.bulkUpdate` and
  `requestAuth` without matching slack-api-ref request definitions.
  `apps.user.connection.update` already has both inputs and is generated on the base.
- slack-api-ref lists `message.session` without a java-slack-sdk event class or
  recorded payload. The guest-status event and the agent-session title event's
  `enterprise_id` placement still lack the inputs noted below.
- The slack-api-ref assistant-search partial failure metadata lacks a Java
  response fixture. Other documentation-only response examples, rate limits and
  error lists do not change Java-derived response shapes.
- File-upload blocks are already accepted by swift-slack
  `files.completeUploadExternal` and encoded by its form middleware. Java's upload
  convenience helper, Java async rate-limit configuration and client wiring have
  no equivalent in the downstream implementation. Swift already tolerates
  malformed streaming `Retry-After` values and rejects null or empty typed
  response bodies. Java metrics, packaging, release tooling and Kotlin-specific
  builder changes do not require downstream changes.

### Verification

With Swift 6.4.0 and Ruby 4.0.7, `bundle install`, `make test-scripts`
(138 tests, 440 assertions), `make check-fixtures` (292 Web API responses and
95 events, zero unexplained mismatches) and `swift test` (264 tests across 36
suites) passed. Two full `make generate` runs produced identical hashes for
all 404 generated Swift files and `Package.swift`. `git diff --check` passed.

## Review on 2026-10-17

Sync PR: #265.

| Source | Previous commit | Reviewed snapshot |
| --- | --- | --- |
| [java-slack-sdk](https://github.com/slackapi/java-slack-sdk) | `9894c9331565ec8484fa07e4b292bf719a67fcba` | `383dd5f35085b700db5c926add4705a8e8df56ee` |
| [slack-api-ref](https://github.com/slack-ruby/slack-api-ref) | `0fcbcec7c842b5b3880fa7c0d7fb3d66fe1de711` | `9d12de7552102bcacb8cb72162063a39b7b6d9b9` |

Both branch heads were fetched live and are descendants of the previous pins.
The base and PR target are `release-2027-01`, at
`703a9afc8d3c21117f521d4ae0c533fe44f42820` for this review.

### Implemented

- Added handwritten downstream swift-slack `AuthProviderBlock`, `Block.authProvider`
  and DSL `BlockComponent` support, matching upstream java-slack-sdk's Java class,
  Gson layout-block dispatch and Kotlin builder. All thirteen JSON fields are
  represented, including the discriminator, accessory and fallback blocks. As in
  existing handwritten blocks, required fields are nonoptional, text fields use
  `TextObject`, and URLs use `URL`; callers must supply plain-text objects for this
  block's text fields.
- **BREAKING**: exhaustive switches over downstream swift-slack `Block` must handle
  `.authProvider`. No existing cases or operations are removed. Tests preserve every
  field through decode/encode for both complete and minimal upstream Java examples,
  and cover DSL composition and nested fallback blocks.
- Regenerated request comments from upstream slack-api-ref: the privacy inheritance
  and explicit override rules for `agents.conversations.create.is_private`, and
  markdown/task-update chunks for `chat.appendStream`. No request field shapes change.
  The nine `agents.conversations.*` methods are already generated on this base.

### Reviewed exclusions and coverage gaps

- Upstream java-slack-sdk adds `apps.user.connection.bulkUpdate` and `requestAuth`
  classes and response fixtures. Upstream slack-api-ref supplies neither method's
  request definition, so neither operation is generated. No response fixture keys
  are missing from the corresponding Java classes; no added overrides are needed.
- Upstream java-slack-sdk changes no Events classes or fixtures in this delta.
  Handwritten Bolt runtime behavior is unaffected. The two copied agent-session
  event payloads remain valid; neither has gained a recorded upstream fixture.
  The previously documented `agent_session_title_changed.enterprise_id` placement
  gap remains: the Slack reference documents the event field, while java-slack-sdk
  declares it on the callback envelope. No recorded event payload resolves this.
- Existing missing-fixture methods remain excluded, including seven
  `admin.usergroups.*` methods (`addUsers`, `create`, `fetch`, `removeTeams`,
  `removeUsers`, `update`, `uploadUsers`) and `canvases.getContent`. `user_guest_status_changed` still lacks a Java event model
  and complete test payload usable for generation.
- Upstream slack-api-ref adds documentation-only `rich_link_preview_type` to
  `admin.apps.config.lookup`, `channel_type` to `assistant.search.context` channels,
  and failed user/channel ID lists to `slackLists.access.delete` examples. The Java
  lookup and access-delete fixtures do not carry these fields; assistant search
  has no response fixture. These remain coverage gaps, not added overrides.
- Upstream slack-api-ref corrects the team object in `admin.teams.settings.info`,
  user nesting in `admin.users.getExpiration`, and string job ID in
  `slackLists.download.start`; downstream swift-slack already follows these Java
  response shapes. Required flags on agent-session output, optional invite links,
  a misplaced history field, and a generic kick-errors object are documentation
  response corrections; they do not replace Java-derived response inputs.
- The remaining slack-api-ref changes are error descriptions, examples (including
  Slack Lists item creation), rate metadata, analytics descriptions and the method
  index. The `admin.apps.permissions.set.usergroup_ids` comment concerns a method
  without a Java response fixture and stays excluded. No SDK rate-tier table needs
  updating. Upstream Java client wiring, form serialization, rate constants and
  Kotlin-specific builder mechanics have no further downstream Swift counterpart.

### Verification

`bundle install`, full `make generate`, `make check-fixtures` and `swift test`
passed using Swift 6.4.0 and Ruby 4.0.7. The fixture scan found zero unexplained
mismatches across 370 payloads; all 277 response and 93 event fixtures decoded.
The root suite passed 225 tests across 34 suites, including both auth-provider
payloads, all public fields and DSL composition. The copied test payloads were
also compared with their upstream Java originals and matched.

A second complete `make generate` produced identical hashes for all 395 generated
Swift files and `Package.swift` (396 hashes total). No generated files were added or deleted,
and the trait list is unchanged. Scripts were not changed, so `make test-scripts`
was not required. Handwritten changed files were formatted and `git diff --check`
passed. Live Slack integration was not run.

## Maintaining this record

For each reviewed sync, replace the snapshot table with the new gitlinks and
record the review date, previous SHAs, covered upstream areas, implemented changes,
intentional exclusions, and unresolved gaps. Include the sync PR reference once
available. Preserve these structural sections. Record stable local verification
facts here; keep hosted CI status in the PR body, not this file.

A no-op requires live upstream access and comparison against current `origin/main`.
Scheduled runs may persist reviewed-through SHAs, the main SHA, decisions and known
gaps in run memory to avoid repeating unchanged reviews; see the sync skill for
ancestry and invalidation rules. Repository pins remain unchanged on a no-op.
Review coverage applies to the selected delta, not complete historical or live parity.
