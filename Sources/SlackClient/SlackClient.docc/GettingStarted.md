# Getting Started

Set up `SlackClient` and make your first Web API calls.

## Installation

Add swift-slack and a transport package to your `Package.swift`. This example uses AsyncHTTPClient:

```swift
dependencies: [
    .package(url: "https://github.com/ainame/swift-slack.git", from: "2026.10.1"),
    .package(url: "https://github.com/swift-server/swift-openapi-async-http-client.git", from: "1.1.0"),
],
```

Then add both products to your target:

```swift
.target(
    name: "MyTool",
    dependencies: [
        .product(name: "SlackClient", package: "swift-slack"),
        .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
    ]
)
```

To compile only the Web API groups you call, select package traits. See <doc:Traits>.

## Create a client

```swift
import OpenAPIAsyncHTTPClient
import SlackClient

let slack = Slack(
    transport: AsyncHTTPClientTransport(),
    configuration: .init(token: "xoxb-your-bot-token")
)
```

Web API operations are methods on `slack.client`. Each method is named after the Slack method, so `chat.postMessage` becomes `chatPostMessage`.

## Send a message

Pass the request as a JSON body:

```swift
try await slack.client.chatPostMessage(
    body: .json(.init(
        channel: "#general",
        text: "Hello from Swift!"
    ))
)
```

## Read a response

Each call returns the generated output type. Unwrap the successful JSON body, then check Slack's `ok` flag:

```swift
let output = try await slack.client.conversationsInfo(
    body: .json(.init(channel: "C1234567890"))
)
let response = try output.ok.body.json

if response.ok {
    print("Channel name: \(response.channel?.name ?? "Unknown")")
} else {
    print("Slack error: \(response.error ?? "unknown")")
}
```

## Next steps

To receive events, slash commands, and interactions, use the `SlackKit` product. It includes this client and adds the `SlackApp` runtime for Socket Mode and HTTP apps.
