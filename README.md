# swift-slack

<p align="center">
<img src="./logo.svg" alt="swift-slack logo" width="160">
</p>

**Build Slack apps in Swift.**\
Typed Web API, Bolt-style routing, and a SwiftUI-style Block Kit DSL.

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
![Platforms: macOS | Linux](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux-lightgrey.svg)
[![GitHub Release](https://img.shields.io/github/v/release/ainame/swift-slack)](https://github.com/ainame/swift-slack/releases)
[![Build Status](https://img.shields.io/github/actions/workflow/status/ainame/swift-slack/test.yml?branch=main)](https://github.com/ainame/swift-slack/actions)
[![Documentation](https://img.shields.io/badge/docs-DocC-blue.svg)](https://ainame.github.io/swift-slack/)
[![MIT License](https://img.shields.io/badge/license-MIT-yellow.svg)](https://github.com/ainame/swift-slack/blob/main/LICENSE)

[Get started](#get-started) · [Examples](#examples) · [Documentation](https://ainame.github.io/swift-slack/documentation) · [Releases](https://github.com/ainame/swift-slack/releases)

> [!IMPORTANT]
> **Upgrading from 2026.9.x or earlier?** Releases 2026.10.0 through 2026.10.2 include changes that may need code updates.
>
> * **Use `router.onAction(_:blockId:)` instead of the deprecated `router.onBlockAction(_:)`.** `onBlockAction` was implemented incorrectly: it matched the view's `callback_id` instead of the element's `action_id`, so it couldn't handle buttons or other elements in messages. `onAction` matches by `action_id`, like Bolt's `app.action(...)`, and works in messages, modals, and App Home. Read selected values from `payload.blockActions` instead of `payload.actions`. Both `onBlockAction` and `payload.actions` will be removed in a 2027 release ([#156](https://github.com/ainame/swift-slack/issues/156)). To see which ID to match, read [Choosing Between action_id and callback_id](https://ainame.github.io/swift-slack/documentation/slackapp/interactionidentifiers).
> * **2026.10.0 removed 17 Web API operations that 2026.9.x generated incorrectly.** Their response types were mostly empty, often with only an `ok` field, so they returned little useful data. They'll come back once they can be generated properly.
> * 2026.10.2 has a few small breaking changes, such as the new `InteractivePayload.blockSuggestion` case and `onView` becoming a fallback for `onViewSubmission` and `onViewClosed`.
>
> See the [CHANGELOG](CHANGELOG.md) for details and migration steps.

```swift
import SlackKit

let router = Router()

// Reply when someone mentions your app
router.onEvent(AppMentionEvent.self) { context, _, event in
    guard let channel = event.channel, let user = event.user else { return }
    try await context.say(text: "Hi <@\(user)>! 👋", channel: channel)
}

// Handle a slash command
router.onSlashCommand("/echo") { context, payload in
    try await context.ack()
    try await context.say(text: "Echo: \(payload.text)", channel: payload.channelId)
}

let app = SlackApp(
    configuration: .init(appToken: appToken, token: token),
    router: router,
    mode: .socketMode() // no public URL needed
)

try await app.run()
```

## Features

Use as much of the stack as you need:

- **`SlackClient`**: a standalone Web API client for scripts, CLIs, and CI jobs. No app runtime required.
- **`SlackKit`**: a Bolt-style app framework for interactive apps, with routing, acknowledgements, Socket Mode, and HTTP. It includes the Web API client.

Highlights:

- **Over 260 typed Web API methods.** Call `chat.postMessage`, `views.open`, `conversations.history`, and more with Swift request and response models.
- **Over 90 typed Events API payloads.** Register `router.onEvent(AppMentionEvent.self)` and receive a decoded struct, not a JSON dictionary.
- **Socket Mode or HTTP.** Connect over WebSocket without a public endpoint, or receive signed HTTP requests in production.
- **SwiftUI-style Block Kit DSL.** Compose messages, modals, and App Home tabs from reusable Swift views.
- **Swift 6 concurrency.** `async`/`await` handlers, `Sendable` types, and `swift-service-lifecycle` integration.
- **macOS and Linux.** CI runs the test suite on Linux, so the same app deploys to servers and containers.

The Web API client is generated with [swift-openapi-generator](https://github.com/apple/swift-openapi-generator), so it works with any transport from that ecosystem, such as [AsyncHTTPClient](https://github.com/swift-server/swift-openapi-async-http-client) or [URLSession](https://github.com/apple/swift-openapi-urlsession).

## Get started

Build a bot that replies to `/echo` using Socket Mode, without a public HTTP endpoint.
Requires Swift 6.2+ and macOS 14+ or Linux, plus a Slack workspace where you can install apps.

Only need Web API calls? Jump to [Use the Web API client](#use-the-web-api-client).

### 1. Create your Slack app

In [Slack app settings](https://api.slack.com/apps):

1. Create an app and enable **Socket Mode**.
2. Under **Basic Information**, create an app-level token with the `connections:write` scope.
3. Under **OAuth & Permissions**, add the bot scopes `commands` and `chat:write`.
4. Under **Slash Commands**, create `/echo` with a short description and a usage hint such as `[message]`.
5. Install the app to your workspace and copy its **Bot User OAuth Token**.

### 2. Create a Swift package

```bash
mkdir EchoBot
cd EchoBot
mkdir -p Sources/EchoBot
```

Save this as `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoBot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/ainame/swift-slack.git",
            from: "2026.10.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "EchoBot",
            dependencies: [
                .product(name: "SlackKit", package: "swift-slack")
            ]
        )
    ]
)
```

Save this as `Sources/EchoBot/main.swift`:

```swift
import Foundation
import SlackKit

let environment = ProcessInfo.processInfo.environment
guard let token = environment["SLACK_OAUTH_TOKEN"],
      let appToken = environment["SLACK_APP_LEVEL_TOKEN"] else {
    fatalError("Set SLACK_OAUTH_TOKEN and SLACK_APP_LEVEL_TOKEN")
}

let router = Router()

router.onSlashCommand("/echo") { context, payload in
    try await context.ack()
    try await context.say(text: "Echo: \(payload.text)", channel: payload.channelId)
}

let app = SlackApp(
    configuration: .init(appToken: appToken, token: token),
    router: router,
    mode: .socketMode()
)

try await app.run()
```

### 3. Run it

```bash
export SLACK_OAUTH_TOKEN="xoxb-your-bot-token"
export SLACK_APP_LEVEL_TOKEN="xapp-your-app-level-token"
swift run EchoBot
```

Invite the bot to a channel, then type `/echo Hello from Swift` there. The bot replies with **Echo: Hello from Swift**.

## Coming from Bolt

If you have built Slack apps with Bolt for JavaScript or Python, the same concepts apply. A `Router` registers handlers in place of `app`, and each handler receives a context with `ack()`, `say()`, and the Web API `client`. Events are acknowledged automatically, as in Bolt.

| Bolt for JavaScript                | swift-slack                                              |
| ---------------------------------- | -------------------------------------------------------- |
| `app.event('app_mention', ...)`    | `router.onEvent(AppMentionEvent.self) { ... }`           |
| `app.command('/echo', ...)`        | `router.onSlashCommand("/echo") { ... }`                 |
| `app.shortcut('callback_id', ...)` | `router.onGlobalShortcut("callback_id") { ... }`         |
| `app.action('action_id', ...)`     | `router.onAction("action_id") { ... }`                   |
| `app.view('callback_id', ...)`     | `router.onViewSubmission("callback_id") { ... }`         |
| `app.options('action_id', ...)`    | `router.onBlockSuggestion("action_id") { ... }`          |
| `await ack()` / `await say(...)`   | `try await context.ack()` / `try await context.say(...)` |
| `client.chat.postMessage({...})`   | `context.client.chatPostMessage(body: .json(...))`       |
| `socketMode: true`                 | `mode: .socketMode()`                                    |

## Examples

| Build | Explore |
| --- | --- |
| Translate messages using flag reactions or shortcuts | [DeepL translator](DemoApps/deepl-translator) |
| Compose interactive messages, modals, and an App Home | [Block Kit DSL app](DemoApps/Examples/Sources/dsl/Command.swift) |
| Reply to slash commands publicly or privately | [Echo bot](DemoApps/Examples/Sources/echoSlashCommand/Command.swift) |
| Handle typed Slack events and interactions | [Router example](DemoApps/Examples/Sources/router/Command.swift) |
| Load external select menu options as the user types | [External select](DemoApps/Examples/Sources/externalSelect/Command.swift) |

Browse [all examples](DemoApps/Examples) for more patterns.

## Build reusable Block Kit views

Add the `SlackBlockKitDSL` product to your target to compose messages and modals with result builders:

```swift
.product(name: "SlackBlockKitDSL", package: "swift-slack")
```

```swift
import SlackBlockKitDSL
import SlackKit

let approval = Section {
    Text("Ready to ship?").type(.mrkdwn)
}
.accessory(
    Button("Approve").actionId("approve").style(.primary)
)

struct WelcomeModal: SlackModalView {
    var title: TextObject { "Welcome" }
    var submit: TextObject? { "Continue" }

    var blocks: [Block] {
        Header { Text("Getting Started") }
        Section { Text("Welcome to our app!") }
        Input {
            PlainTextInput()
                .actionId("name_field")
                .placeholder("Enter your name")
        } label: {
            Text("Your Name")
        }
    }
}
```

Prefer constructing models directly? Use `SlackBlockKit`. See the [Block Kit DSL guide](Sources/SlackBlockKitDSL/SlackBlockKitDSL.docc/BlockKitDSL.md) for both styles.

## Use the Web API client

Use `SlackClient` for direct API access. Add the [AsyncHTTPClient transport](https://github.com/swift-server/swift-openapi-async-http-client) package to your dependencies and its `OpenAPIAsyncHTTPClient` product alongside `SlackClient` in your target. Other transports from the Swift OpenAPI ecosystem also work.

```swift
import OpenAPIAsyncHTTPClient
import SlackClient

let slack = Slack(
    transport: AsyncHTTPClientTransport(),
    configuration: .init(token: token)
)

try await slack.client.chatPostMessage(
    body: .json(.init(
        channel: "#general",
        text: "Hello from Swift!"
    ))
)
```

See the [Web API example](DemoApps/Examples/Sources/chatPostMessage/Command.swift) for token configuration and a complete entry point.

## Configure your app

The default package traits include the Web API, events, and Socket Mode. For smaller builds, select only the traits you need:

```swift
.package(
    url: "https://github.com/ainame/swift-slack.git",
    from: "2026.10.2",
    traits: ["SocketMode", "Events", "WebAPI_Chat", "WebAPI_Views"]
)
```

`SocketMode` also enables `WebAPI_Apps`. For HTTP apps, enable `HummingbirdHTTPAdapter` and pass a `HummingbirdAdapter` to `SlackApp` using `mode: .http(adapter)`. You can also implement `HTTPServerAdapter` for another server framework.

Events API handlers are acknowledged automatically. Slash commands, block actions, shortcuts, and view handlers must call `context.ack()`, as in the quickstart.

- [Runtime guide](Sources/SlackApp/SlackApp.docc/GettingStarted.md): HTTP setup, startup hooks, acknowledgements, and `ServiceGroup` integration.
- [Package traits](Sources/SlackClient/SlackClient.docc/Traits.md): choose the APIs and integrations your app needs.
- [API documentation](https://ainame.github.io/swift-slack/documentation): explore the package's modules and types.
- [Migration guide](Sources/SlackApp/SlackApp.docc/MigrationGuide.md): upgrade from 0.5.x to `SlackApp`.
- [Migrating to Java-derived models](MIGRATING_TO_JAVA_DERIVED_MODELS.md): upgrade apps that used `SlackModels` or spell out Web API and event model types.

## Contributing

Issues and pull requests are welcome. If a Web API method or event is missing or decodes incorrectly, [open an issue](https://github.com/ainame/swift-slack/issues) with the payload you received.

To work on the SDK itself, use the Swift and Ruby versions in [`.swift-version`](.swift-version) and [`.ruby-version`](.ruby-version), plus a C compiler for the tree-sitter Java grammar. The development toolchain currently uses Swift 6.4; the package manifest's minimum is Swift 6.2.

```bash
git clone --recursive https://github.com/ainame/swift-slack.git
cd swift-slack
bundle install
make generate
swift test
```

Run `make update` when intentionally advancing the upstream reference data. See [AGENTS.md](AGENTS.md) for the source layout, generator workflow, and contribution checks.

For an agent-reviewed upstream update, invoke `$slack-upstream-sync` using the
repository's [sync skill](.agents/skills/slack-upstream-sync/SKILL.md). It reviews
both vendor deltas, checks generated and handwritten models, and prepares a PR.
The [upstream record](UPSTREAM.md) distinguishes vendor pins from reviewed coverage.
The same Make targets remain available for manual updates; `make generate` alone
regenerates from the currently checked-out vendor snapshots.

Scheduled Codex runs require full access, authenticated Git/GitHub access, and an
isolated worktree based on current `origin/main`. Keep the computer and app running.
Test the skill manually before enabling the schedule. GitHub Actions continues to
test PRs; the Schema Update workflow is a manual fallback and should not run while
an agent sync is running or awaiting review.

Web API request parameters come from [slack-ruby/slack-api-ref](https://github.com/slack-ruby/slack-api-ref). Response and event models are translated from the model classes of [Slack's Java SDK](https://github.com/slackapi/java-slack-sdk) and generated with swift-openapi-generator. Properties other than `ok` are optional, because Slack omits fields depending on the method, the object, and the workspace. Every generated method and event is checked against the Java SDK's recorded payloads (`make check-fixtures`).

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for upstream attribution.

This is an unofficial, community-maintained project, not affiliated with Slack Technologies, LLC.
