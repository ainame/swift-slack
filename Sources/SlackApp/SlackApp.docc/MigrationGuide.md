# Migration Guide

Move app runtime code from `SlackClient` 0.5.x to `SlackApp` and `SlackKit`.

## Overview

Release 0.6.0 split the app runtime out of `SlackClient`. `SlackClient` became the Web API layer, and the new `SlackApp` module took over:

- `SlackApp`, `Router`, and `Ack`
- Events API payload types
- Socket Mode
- HTTP request verification and server adapters

## Update dependencies and imports

Depend on the `SlackKit` product, which re-exports `SlackApp`, `SlackClient`, and `SlackBlockKit`:

```swift
.target(
    name: "MySlackApp",
    dependencies: [
        .product(name: "SlackKit", package: "swift-slack"),
    ]
)
```

Then replace `import SlackClient` with `import SlackKit` in app code.

## Update Socket Mode startup

Before:

```swift
let router = SocketModeRouter()
await slack.addSocketModeRouter(router)
try await slack.runInSocketMode()
```

After:

```swift
let router = Router()
let app = SlackApp(
    configuration: .init(appToken: appToken, token: token),
    router: router,
    mode: .socketMode()
)
try await app.run()
```

## Update HTTP apps

HTTP request handling moved to `SlackApp`. Enable the `HummingbirdHTTPAdapter` trait and pass a `HummingbirdAdapter`:

```swift
let router = Router()
let adapter = HummingbirdAdapter(hostname: "0.0.0.0", port: 8080)
let app = SlackApp(
    configuration: .init(token: token, signingSecret: signingSecret),
    router: router,
    mode: .http(adapter)
)
try await app.run()
```

## Renamed and moved symbols

- `SocketModeRouter` is now `Router`.
- `Slack.runInSocketMode(...)` is now `SlackApp(..., mode: .socketMode()).run()`.
- `Slack.addSocketModeRouter(...)` was removed. Pass the router to `SlackApp` instead.
- Hummingbird support moved to `HummingbirdAdapter`.
- Events API payload types such as `Event`, `MessageEvent`, and `AppMentionEvent` moved from `SlackClient` to `SlackApp`.
- `onSlackMessageMatched(...)` was removed. Register `onEvent(MessageEvent.self)` and filter inside the handler.

## Acknowledgement changes

`SlackApp` acknowledges Events API requests the way Bolt does:

- `onEvent` handlers are acknowledged automatically and don't receive `ack`. In HTTP mode, Events API requests return `200 OK`; in Socket Mode, the envelope is acknowledged before dispatch.
- Slash command, interaction, shortcut, and view handlers still call `ack()` explicitly.
- Registering another handler of the same kind for the same command, callback ID, action ID, or event type replaces the earlier one and logs a warning with the `SlackApp.Router` logger label. `onViewSubmission` and `onViewClosed` can share a callback ID, and `onView` handles only the view payload types that have no type-specific handler.

## ServiceLifecycle

`SlackApp` conforms to `Service`, so you can run it in a `ServiceGroup`. See <doc:GettingStarted#Running-with-ServiceLifecycle>.
