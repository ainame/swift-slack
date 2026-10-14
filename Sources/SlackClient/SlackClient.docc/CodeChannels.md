# Code channels

Show an agent's work in a Slack Code channel with typed properties, commands, and views.

## Overview

A Slack Code channel is a channel where the whole channel is one agent session. Enable the `WebAPI_Agents` package trait (see <doc:Traits>) and give the app the `code_channels:manage` scope. In the app manifest, set `features.code_channels.enabled` to `true`; with signed HTTP requests, also set `slash_command_url`, which Socket Mode apps leave out. The generated `AppManifest.FeaturesPayload.codeChannels` models `enabled` and `slashCommandUrl`, so these settings can also be encoded from Swift.

The typed helpers on your Slack client cover the calls that take structured arguments:

- ``APIProtocol/setCodeChannelProperties(channelId:properties:agentResource:)``
- ``APIProtocol/setCodeChannelCommands(channelId:commands:)``
- ``APIProtocol/setCodeChannelView(channelId:view:)``

Each returns Slack's response, including its `warning`, and throws ``CodeChannel/Error`` when Slack answers `"ok": false`. Transport and unexpected HTTP failures propagate unchanged. The generated methods, such as `agentsConversationsSetView`, remain available for arguments the helpers do not cover.

### Create and end the channel

Create, archive, and title the channel with the generated methods. When to create or archive a channel is up to your app.

```swift
let output = try await client.agentsConversationsCreate(body: .json(.init(
    name: "fix-login-bug",
    originChannelId: event.channel,
    originMessageTs: event.ts,
)))

// Select the HTTP 200 response. This throws for an unexpected HTTP status.
let httpResponse = try output.ok

// Extract the decoded Slack response. HTTP 200 does not guarantee Slack accepted the request.
let response = try httpResponse.body.json
guard response.ok, let channelId = response.channelId else { return }

try await client.agentsSessionsRename(body: .json(.init(channelId: channelId, title: "Fix the login bug")))
try await client.agentsSessionsSetStatus(body: .json(.init(channelId: channelId, status: "active")))

// When the work is done:
try await client.agentsConversationsArchive(body: .json(.init(channelId: channelId)))
```

The session methods need the `chat:write` scope. Leave out `threadTs` in code channels, both in these calls and when streaming replies with ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)`` (see <doc:StreamingMessages>).

### Set the context bar and resource

```swift
try await client.setCodeChannelProperties(
    channelId: channelId,
    properties: .init(
        contextBarItems: [
            .init(key: "branch", label: "fix-login", icon: .branch),
            .init(key: "ci", label: "CI", icon: .terminal, url: ciURL, itemType: .info),
        ],
        summaryMessage: .init(messageTs: summaryTs),
    ),
    agentResource: .init(url: repositoryURL, resourceType: "repository", provider: "github"),
)
```

Slack updates only the properties you send, and answers `no_properties_provided` when you send none. `contextBarItems` replaces the whole bar: Slack keeps the first 5 items and adds a `warning` when you send more, and treats an `action` item that has a `url` as `info`, also with a `warning`. Set the session's title and status with `agentsSessionsRename` and `agentsSessionsSetStatus` rather than `setProperties`.

### Register commands

```swift
try await client.setCodeChannelCommands(
    channelId: channelId,
    commands: [
        .init(name: "review", description: "Review the current diff"),
        .init(name: "run", description: "Run a task", argumentHint: "[task]"),
    ],
)
```

The array replaces the commands your app registered in the channel; pass `[]` to clear them. A channel holds at most 10 commands across all agents. Register names without the slash: SlackApp's `Router.onSlashCommand` receives them with it, such as `/review`.

### Show views

```swift
try await client.setCodeChannelView(
    channelId: channelId,
    view: .html(key: "report.html", content: html, csp: .init(resourceDomains: ["https://cdn.example.com"])),
)
try await client.setCodeChannelView(
    channelId: channelId,
    view: .diff(content: diff, baseBranch: "main", headBranch: "fix-login"),
)
try await client.setCodeChannelView(
    channelId: channelId,
    view: .canvas(key: "notes", canvasId: canvasId, accessLevel: .comment),
)
```

Calls with the same `key` update the same view; a diff view is one per channel, so it takes no key. HTML and diff content is limited to 1,000,000 bytes. Slack honors only `resourceDomains` of an HTML view's ``CodeChannel/CSP`` today and stores `connectDomains` without applying them. A canvas view with `accessLevel: .comment` keeps channel members from editing it; `agentContentHash` is opaque to Slack, for detecting edits by people later.

Slack enforces these limits. The helpers do not check them, so a request beyond a limit fails with Slack's error code or succeeds with a `warning`.

### Read channel properties and receive actions

`conversationsInfo` returns the code channel's `summaryMessage`, `agentSessionViews`, and
context bar `itemType` under `channel.properties.codeChannel`. The canonical channel
view entries expose `name` and `type`; `agentsConversationsListViews` keeps `label`,
as specified by that method's reference. Recognize code channels using
`channel.properties.recordChannel.recordType == "agent_channel"`.

SlackApp routes context-bar clicks through `CodeChannelActionEvent`:

```swift
router.onEvent(CodeChannelActionEvent.self) { context, envelope, event in
    // Slack has not published a field schema for this event. Inspect the arbitrary
    // JSON fields in event.additionalProperties.value for your app's payload.
}
```

### Schema provenance and remaining limits

Upstream java-slack-sdk does not yet declare these additional response fields or
`features.code_channels`. Downstream swift-slack generates them from the narrow
Slack Code supplement in `scripts/slack_code_schemas.yml`, sourced from
[Slack's channel properties contract](https://docs.slack.dev/ai/slack-code/code-channel-properties/)
and [manifest configuration](https://docs.slack.dev/ai/slack-code/agent-slash-commands/).
The generator fails when upstream adopts a supplemented field or the action event,
so that upstream models and fixtures can replace the exception.

This supplement is temporary. When upstream java-slack-sdk officially models
these fields and events, swift-slack will migrate the corresponding generation
inputs to those declarations and their upstream fixtures, removing each adopted
exception. The migration will retain the decode/re-encode and event-routing
regression coverage, compare wire shapes and generated Swift APIs, and preserve
source compatibility where possible. Any required public API changes will be
explicitly documented in the changelog; upstream adoption will not silently
replace the downstream contract.

Slack documents `code_channel_action` but does not publish its payload schema.
`CodeChannelActionEvent` therefore models only `type` and preserves every other
JSON field in `additionalProperties`. Its regression payload is synthetic; it
establishes lossless decoding and routing, not a typed or live-verified action contract.

## Topics

### Helpers

- ``APIProtocol/setCodeChannelProperties(channelId:properties:agentResource:)``
- ``APIProtocol/setCodeChannelCommands(channelId:commands:)``
- ``APIProtocol/setCodeChannelView(channelId:view:)``

### Request values

- ``CodeChannel``
