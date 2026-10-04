# ``SlackKit``

Build Slack apps in Swift with one import.

## Overview

`SlackKit` is the recommended product for app code. It re-exports:

- `SlackApp`, the runtime for Socket Mode and HTTP apps, with routing, acknowledgements, and Events API payload types
- `SlackClient`, the Web API client, along with the shared `SlackModels` types
- `SlackBlockKit`, the Block Kit models for messages, modals, and App Home tabs

```swift
import SlackKit

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

To compose Block Kit with a SwiftUI-style syntax, also add the `SlackBlockKitDSL` product and `import SlackBlockKitDSL`.

Depend on `SlackClient` alone when you only call the Web API, such as from a script or CI job.

### Next Steps

- `SlackApp` documentation: Getting Started, examples, and the migration guide from 0.5.x
- `SlackClient` documentation: Web API usage and package traits
- `SlackBlockKitDSL` documentation: the Block Kit DSL guide and examples
