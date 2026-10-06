# Getting Started

Run a Slack app over Socket Mode or HTTP, and handle its events and interactions.

## Installation

Add swift-slack to your package and depend on the `SlackKit` product, which includes this runtime and the Web API client:

```swift
dependencies: [
    .package(url: "https://github.com/ainame/swift-slack.git", from: "2026.10.1"),
],
targets: [
    .executableTarget(
        name: "MySlackApp",
        dependencies: [
            .product(name: "SlackKit", package: "swift-slack"),
        ]
    ),
]
```

The default traits include Socket Mode, Events API payloads, and every Web API group. To serve HTTP requests with Hummingbird, or to compile fewer Web API groups, see the `SlackClient` documentation on traits.

## Socket Mode

Socket Mode connects to Slack over a WebSocket, so your app doesn't need a public URL. It needs an app-level token with the `connections:write` scope and a bot token:

```swift
import SlackKit

let router = Router()

// Events are acknowledged automatically
router.onEvent(AppMentionEvent.self) { context, _, event in
    guard let channel = event.channel, let user = event.user else { return }
    try await context.say(text: "Hi <@\(user)>! 👋", channel: channel)
}

// Slash commands must be acknowledged
router.onSlashCommand("/hello") { context, payload in
    try await context.ack()
    try await context.say(text: "Hello, \(payload.userName)!", channel: payload.channelId)
}

let app = SlackApp(
    configuration: .init(appToken: appToken, token: token),
    router: router,
    mode: .socketMode()
)

try await app.run()
```

To use the Web API client before the runtime starts, pass a `preparing` closure:

```swift
try await app.run { slack in
    _ = try await slack.client.authTest()
}
```

## HTTP

An HTTP app receives signed requests from Slack. Enable the `HummingbirdHTTPAdapter` trait, then pass a `HummingbirdAdapter` and your signing secret:

```swift
import SlackKit

let router = Router()
let adapter = HummingbirdAdapter(hostname: "0.0.0.0", port: 8080)

let app = SlackApp(
    configuration: .init(token: token, signingSecret: signingSecret),
    router: router,
    mode: .http(adapter)
)

try await app.run()
```

To use another server framework, implement `HTTPServerAdapter` and pass it to `.http(_:)`:

```swift
import SlackKit

struct MyHTTPAdapter: HTTPServerAdapter {
    func run(handler: @escaping HTTPServerHandler) async throws {
        // Convert each incoming request into an HTTPRequest and its body Data,
        // call handler, then write the returned HTTPResponse and body.
    }
}
```

## Handlers and acknowledgements

Slack requires an acknowledgement within three seconds of delivering a request.

- Events API handlers registered with `onEvent` are acknowledged automatically. They receive an `EventContext`, which has no `ack`.
- Slash command, interaction, shortcut, and view handlers receive a `Context` and must call `ack()`. Acknowledge first, then do slower work.
- View submission handlers can acknowledge with `ack(responseAction:view:)` to update or push a view, or `ack(errors:)` to show validation errors.
- Registering another handler for the same command, callback ID, or event type replaces the earlier one.

Both context types provide `client` for Web API calls, `say` to post a message, `respond` to reply through a response URL, and `logger`.

## Block actions

`onAction(_:blockId:handler:)` matches the `action_id` of the interacted element, like Bolt's `app.action(...)`, for buttons and menus in messages, modals, and App Home. Pass `blockId:` to also require the `block_id`. Each action's ID and selected values are in the payload's `blockActions`.

```swift
router.onAction("approve") { context, payload in
    try await context.ack()
    print(payload.blockActions.first?.value ?? "")
}

router.onAction("approve", blockId: "request_42") { context, payload in
    try await context.ack()
}
```

To handle every action in a view, use `onInteractive(_:)` and check the payload's `callbackId`.

`onBlockAction(_:)` is deprecated because it was implemented incorrectly: it does not match Bolt, which matches the element's `action_id`, and matches the containing view's `callback_id` instead. It will be removed in a 2027 release. Replace it with `onAction(_:blockId:handler:)` for each element, or with `onInteractive(_:)` for a whole view.

## Events API payload types

With the `Events` trait enabled, `SlackApp` provides typed payloads for Events API events, such as `MessageEvent`, `AppMentionEvent`, and `ReactionAddedEvent`. Register a handler for one event type with `onEvent(_:handler:)`, or receive every event as an `Event` value with `onEvent(_:)`.

## Running with ServiceLifecycle

`SlackApp` conforms to `Service`, so you can run it in a `ServiceGroup` with other services and shut it down gracefully. Add the [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) package and its `ServiceLifecycle` product to your target:

```swift
import Logging
import ServiceLifecycle
import SlackKit

let app = SlackApp(
    configuration: .init(appToken: appToken, token: token),
    router: router,
    mode: .socketMode()
)

let group = ServiceGroup(
    services: [app],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: Logger(label: "MySlackApp")
)

try await group.run()
```
