# ``SlackClient``

Call the Slack Web API with typed requests and responses.

## Overview

`SlackClient` is the Web API layer of the `swift-slack` package. Use it on its own for scripts, CLIs, and CI jobs, or through `SlackKit` inside an app. It provides:

- ``Slack``, which configures authentication and middleware for a transport you choose
- generated Web API operations on ``Slack/client``, such as `chatPostMessage` and `viewsOpen`
- request and response models in `Components.Schemas`, with top-level aliases such as `User` and `Message` for the shared models

For Socket Mode, signed HTTP requests, routing, acknowledgements, and Events API payload types, use `SlackKit`, which adds the `SlackApp` runtime on top of this module.

### Choose a transport

`SlackClient` is generated with [swift-openapi-generator](https://github.com/apple/swift-openapi-generator), so it works with any `ClientTransport` from that ecosystem, such as [AsyncHTTPClient](https://github.com/swift-server/swift-openapi-async-http-client) on servers or [URLSession](https://github.com/apple/swift-openapi-urlsession) in Apple-platform apps.

### Where the API comes from

Web API methods and request parameters come from the community-maintained [slack-api-ref](https://github.com/slack-ruby/slack-api-ref). Response models are inferred from the recorded responses in Slack's official [java-slack-sdk](https://github.com/slackapi/java-slack-sdk), so a method is available only when that SDK has a response sample for it. Many response properties are optional because they are inferred from samples.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Traits>
- ``Slack``
