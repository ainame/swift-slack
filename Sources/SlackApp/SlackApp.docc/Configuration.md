# Configuration

Load your app's tokens and signing secret from the environment or from swift-configuration, and develop with the Slack CLI.

## Overview

`SlackApp` reads its credentials from `Slack.Configuration`, which `SlackApp.Configuration` aliases:

| Property | Slack credential | Needed for |
| --- | --- | --- |
| `token` | Bot User OAuth Token (`xoxb-`) | Web API calls |
| `appToken` | App-level token (`xapp-`) with `connections:write` | Socket Mode |
| `signingSecret` | Signing secret | Verifying HTTP requests |

You can pass these values to `init(userAgent:appToken:token:signingSecret:)` yourself, or let swift-slack read them from the conventional variables `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, and `SLACK_SIGNING_SECRET`. Bolt apps read the same variables. For `slack run`, the Slack CLI sets `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN` to its development app's tokens, but not `SLACK_SIGNING_SECRET`: an HTTP app must supply its signing secret itself.

## Read environment variables

`Slack.Configuration.fromEnvironment(userAgent:)` reads the three variables from the process environment. It needs no extra dependencies:

```swift
import SlackKit

let app = SlackApp(
    configuration: .fromEnvironment(userAgent: "EchoBot/1.0"),
    router: router,
    mode: .socketMode()
)

try await app.run()
```

A variable that is unset, empty, or only whitespace leaves its property `nil`, so a Web API script can set `SLACK_BOT_TOKEN` alone. Surrounding whitespace is trimmed.

## Use swift-configuration

The `SwiftConfiguration` trait adds `Slack.Configuration(config:userAgent:)`, which reads the same values from a [swift-configuration](https://github.com/apple/swift-configuration) `ConfigReader`. Use it when your app already loads its settings with swift-configuration, for example from a `.env` file in development and a JSON file or a secrets store in production.

Enable the trait alongside the default traits, and add swift-configuration for `ConfigReader` and its providers:

```swift
dependencies: [
    .package(
        url: "https://github.com/ainame/swift-slack.git",
        from: "2027.1.0-beta.5",
        traits: [.defaults, "SwiftConfiguration"]
    ),
    .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
],
targets: [
    .executableTarget(
        name: "EchoBot",
        dependencies: [
            .product(name: "SlackKit", package: "swift-slack"),
            .product(name: "Configuration", package: "swift-configuration"),
        ]
    ),
]
```

Then pass your reader to the initializer:

```swift
import Configuration
import SlackKit

let reader = ConfigReader(providers: [
    EnvironmentVariablesProvider(),
    try await EnvironmentVariablesProvider(environmentFilePath: ".env", allowMissing: true),
])

let app = SlackApp(
    configuration: .init(config: reader, userAgent: "EchoBot/1.0"),
    router: router,
    mode: .socketMode()
)
```

The initializer reads these keys as secrets, so access logs redact them:

| Key | Property | Environment variable |
| --- | --- | --- |
| `slack.botToken` | `token` | `SLACK_BOT_TOKEN` |
| `slack.appToken` | `appToken` | `SLACK_APP_TOKEN` |
| `slack.signingSecret` | `signingSecret` | `SLACK_SIGNING_SECRET` |

`EnvironmentVariablesProvider` maps each key to the variable in the last column, so the same reader works with `slack run`. Other providers nest the keys under `slack`, as in this JSON file:

```json
{
  "slack": {
    "botToken": "xoxb-...",
    "appToken": "xapp-..."
  }
}
```

The trait is off by default, so apps that don't enable it don't resolve swift-configuration.

## Develop with the Slack CLI

[`slack run`](https://docs.slack.dev/tools/slack-cli/) creates a development app from a local manifest, installs it to your workspace, and starts your app with that app's tokens in `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN`. Both approaches above read them without changes.

Add a `manifest.json` with `"socket_mode_enabled": true` to your package directory, and a `.slack/hooks.json` that prints the manifest and runs your app:

```json
{
  "hooks": {
    "get-manifest": "sh -c 'cat manifest.json' get-manifest",
    "start": "sh -c 'swift run EchoBot' start"
  },
  "config": { "sdk-managed-connection-enabled": true }
}
```

Then run:

```bash
slack run
```

- The CLI appends flags such as `--source` to hook commands, so the `sh -c` wrapper drops them.
- `sdk-managed-connection-enabled` lets your app open the Socket Mode connection itself, as `SlackApp` does.
- The CLI sets `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN` only when they are not already set. Unset any you exported for another app before running `slack run`.
- The CLI also passes the variables in your `.env` file, but its tokens take precedence. If your app reads `.env` itself, list the process environment first, as in the reader above.
- Add `.slack/apps.dev.json` to `.gitignore`. The CLI records your development app there.

The [DeepL translator demo](https://github.com/ainame/swift-slack/tree/main/DemoApps/deepl-translator) is set up this way.
