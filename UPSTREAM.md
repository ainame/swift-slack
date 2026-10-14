# Upstream snapshots and review coverage

The submodule gitlinks are the generation inputs. Review coverage applies to the
selected delta, not complete historical parity or live Slack service behavior.

## Slack Code supplement review on 2026-10-14

Supplement PR: #260.

Both upstream remote HEADs still match the recorded generation pins:
java-slack-sdk `9894c9331565ec8484fa07e4b292bf719a67fcba` and
slack-api-ref `0fcbcec7c842b5b3880fa7c0d7fb3d66fe1de711`. No vendor
snapshot was advanced. This review is based on `release-2027-01`.

Downstream swift-slack adds the narrow, approved exception in
`scripts/slack_code_schemas.yml`, using Slack's official
[code channel properties contract](https://docs.slack.dev/ai/slack-code/code-channel-properties/)
and [manifest configuration](https://docs.slack.dev/ai/slack-code/agent-slash-commands/):

- Preserve `summary_message`, `agent_session_views` (including `name` and `type`),
  and context bar `item_type` when decoding/re-encoding channel properties.
- Encode/decode `AppManifest.features.code_channels.enabled` and
  `slash_command_url`.
- Route `code_channel_action` through SlackApp while retaining arbitrary JSON.
  Slack documents its existence but publishes no payload schema. Only `type`
  is modeled; the synthetic regression payload does not establish a typed or
  live-verified event contract.

These are downstream supplements, not additions to upstream java-slack-sdk or
fields observed in its recorded fixtures. Generation fails when upstream declares
an added field or models the action event, requiring adoption of upstream models
and fixtures. Synthetic regression payloads stay separate in
`scripts/slack_code_fixtures/`.

The [listViews method reference](https://docs.slack.dev/reference/methods/agents.conversations.listViews/)
still specifies `label`, matching upstream java-slack-sdk. No `name` or `type`
was added to that response based on the different channel-properties contract.
Adding `Event.codeChannelAction` breaks exhaustive switches; consumers must handle
that new case. No unrelated schema coverage was changed.

Verification: `bundle install`, two full `make generate` passes (all 397 generated
file and manifest hashes matched), `make test-scripts` (143 tests, 460 assertions),
`make check-fixtures` (zero unexplained mismatches and all generated fixtures decoded),
and `swift test` with fixture checks enabled (228 tests) passed with Swift 6.4.0
and Ruby 4.0.7. Swift tests used the native build system with index-store and debug
symbols disabled. `git diff --check` passed. Live Slack integration was not run.

## Review on 2026-10-11

Sync PR: #243.

| Source | Previous commit | Reviewed snapshot |
| --- | --- | --- |
| [java-slack-sdk](https://github.com/slackapi/java-slack-sdk) | `43fad0e0943e53991d9298d08588915116a7a0aa` | `9894c9331565ec8484fa07e4b292bf719a67fcba` |
| [slack-api-ref](https://github.com/slack-ruby/slack-api-ref) | `0ae4e986fbdb824fd4af8ca175ca45142377c8c3` | `0fcbcec7c842b5b3880fa7c0d7fb3d66fe1de711` |

Both branch snapshots were fetched live and are descendants of the previous pins.
The sync is based on the `release-2027-01` branch rather than `origin/main`; both
record the same previous pins.

### Implemented

- Generate the nine `agents.conversations.*` methods (`archive`, `create`,
  `getCanvas`, `listViews`, `removeView`, `setCanvasContent`, `setCommands`,
  `setProperties`, `setView`). slack-api-ref now defines their arguments, which
  closes the gap recorded on 2026-10-03; java-slack-sdk already had their response
  fixtures and response classes. They join the existing `WebAPI_Agents` trait.
- Response types match the Java response classes field by field, including the
  nested `Comment`/`Reply` (`getCanvas`) and `View` (`listViews`) classes. Every
  fixture key is declared, so no `added` override is needed.

### Reviewed exclusions and coverage gaps

- Arguments come from slack-api-ref. It declares `title` and `status` for
  `setProperties` and `label` for `setView`, which java-slack-sdk's request
  builders do not send yet. `commands`, `code_channel`, `agent_resource` and `csp`
  are untyped JSON containers, as for other object arguments.
- `agent_session_stopped` and `agent_session_title_changed` have java-slack-sdk
  event classes and unit-test payloads but no recorded event fixture under
  `json-logs/samples/events`. Since #245 they are generated from copies of those
  unit-test payloads (`scripts/event_fixtures.yml`). For org-level installs, the Slack
  event reference documents an optional `enterprise_id` in the
  `agent_session_title_changed` event itself, while java-slack-sdk models it only on
  the `event_callback` envelope (`AgentSessionTitleChangedPayload`). swift-slack follows
  the Java event class; which placement Slack sends is unverified.
- The java-slack-sdk delta changes only release-note configuration, the maintainers
  guide and documentation links; nothing feeds generation. No Block Kit class,
  event class or handwritten Bolt runtime behavior changed.
- The fixture policy still excludes methods without Java response fixtures, such as
  the `admin.usergroups.*` methods recorded on 2026-10-03.

Coverage applies to the reviewed delta; it is not a claim of full API parity.
This sync changes no exhaustive-switch cases; #245 later adds two `Event` cases.

### Verification

`bundle install`, full `make generate`, `make check-fixtures` (0 unexplained
java-slack-sdk mismatches; every generated response and event decodes its fixture)
and `swift test` passed using the recorded Swift and Ruby versions. A second full
generation pass matched all 532 generated and handwritten Swift file hashes.
Scripts are unchanged, so `make test-scripts` was not rerun. `git diff --check`
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
