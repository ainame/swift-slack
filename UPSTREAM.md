# Upstream snapshots and review coverage

The submodule gitlinks are the generation inputs. Review coverage applies to the
selected delta, not complete historical parity or live Slack service behavior.

## Review on 2026-10-03

Sync PR: #149.

| Source | Previous commit | Reviewed snapshot |
| --- | --- | --- |
| [java-slack-sdk](https://github.com/slackapi/java-slack-sdk) | `dbe498ce0a2f0ed068b4bd7028ce31d22c91998d` | `43fad0e0943e53991d9298d08588915116a7a0aa` |
| [slack-api-ref](https://github.com/slack-ruby/slack-api-ref) | `4f0934e301e9a9a15883ea54fbf8a22efb8e8fc9` | `0ae4e986fbdb824fd4af8ca175ca45142377c8c3` |

Both branch snapshots were fetched live and are descendants of the previous pins.
The sync is based on freshly fetched `origin/main`, rather than Java release tags.

### Implemented

- Preserve `record_channel`, `code_channel`, and `agent_session` from the updated
  `conversations.info` response. Merge the union of conversation `Properties` fields
  across fixtures, also recovering `at_here_restricted`, `at_channel_restricted`, and
  `channel_workflows`. The visitor only wires observed nested handwritten models;
  it does not inject fields into other fixtures. Overlapping field definitions retain
  the existing last-definition policy; unrelated schema names are not unioned.
- Use handwritten `RecordChannel`, `CodeChannel` (with `ContextBarItem`), and
  `AgentSession` (with `OriginLink`), matching the new Java `ConversationProperties`
  fields with explicit coding keys. Stable nested types avoid inferred name collisions.
- Retain the existing public `Properties` type and its fields; new properties are
  optional. The fixture's new `channel.is_open` field is already supported by `Channel`.
- Cover meaningful fixture values, complete new property objects on re-encoding,
  older payloads without these fields, and schema merging across real fixtures.
- Discover handwritten model names from source filenames instead of a maintained
  registry. Generation and standalone extraction share one implementation; generated
  files are excluded from discovery, and `View`/`Block` remain owned by SlackBlockKit.
- Share schema aliases between extraction and Web API reference/import rewriting,
  with coverage for a handwritten `TabData` referenced as `Components.Schemas.Data`.
- Verify that workflow permission dictionaries preserve dynamic `Wf...` keys and
  all existing Java fixture access fields without requiring a model change.

### Reviewed exclusions and coverage gaps

- Nine `agents.conversations.*` response fixtures and their Java request/response
  implementations were inspected. Neither reference tree contains matching request
  definitions, so this sync does not invent their arguments or expose partial methods.
- Six new `admin.usergroups.*` methods and `canvases.getContent` have reference
  definitions but no Java response fixtures. They remain excluded under fixture policy.
- `user_guest_status_changed` adds only event metadata (name, description, scopes),
  with no payload schema or Java event fixture/model. No payload shape is inferred.
- Existing-method changes in the legacy `methods` tree are error descriptions,
  punctuation, and a `slackLists.items.update` example; no request shape changes.
- The `docs.slack.dev` tree adds documentation-only response constraints for
  `admin.workflows.permissions.lookup`, `connector_resource` for function permissions,
  agent-title length limits, and canvas access limits up to 20 IDs. Current generic
  payloads/strings/arrays accept these; this generator uses legacy method definitions
  and Java response fixtures, not documentation response schemas. These documentation
  changes do not add runtime validation or alter generated response types here.
  Removed single-ID limits for Slack Lists access are already accepted by arrays.
- Other documentation changes cover error messages, punctuation, the method/event index, and the `auth.teams.list` rate tier (2 to 3).
  This client does not embed a method-specific rate-tier table.
- Java build dependencies, CI, release machinery, and version metadata have no Swift
  runtime counterpart. No Block Kit class or handwritten Bolt runtime behavior changed.

The unsupported methods/event above are explicit coverage gaps pending upstream
inputs; they are not claims of full API parity. No exhaustive-switch cases change.

### Verification

Fresh `npm ci`, full `make generate`, formatting, `make test-scripts` (26 tests /
94 assertions plus 8 processing tests / 29 assertions), and `swift test` (91 tests
in 16 suites) passed using the recorded Swift and Ruby versions. A second full
generation pass matched all 353 generated/manifest hashes. Visitor tests also passed
outside the repository root. The generated changes are confined to `Properties`
and the newly retained `ChannelWorkflow`; no operations or Events changed.
`git diff --check` passed. Existing binary-property generator warnings are unchanged.
Live Slack integration was not run.

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
