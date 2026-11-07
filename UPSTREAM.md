# Upstream snapshots and review coverage

The submodule gitlinks are the generation inputs. Review coverage applies to the
selected delta, not complete historical parity or live Slack service behavior.

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
