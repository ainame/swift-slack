# ``SlackModels``

Data models for Slack Web API requests and responses.

## Overview

`SlackModels` contains the Swift types that `SlackClient` uses for Web API responses and nested objects, such as users, conversations, messages, and files. `SlackClient` re-exports this module, so you rarely import it directly.

Most models are generated. Their shapes are inferred from the recorded API responses in Slack's [java-slack-sdk](https://github.com/slackapi/java-slack-sdk), so many properties are optional. Where inference produces the wrong type or name, a hand-written model replaces it, following the java-slack-sdk model's name and fields.

Events API payload types live in `SlackApp`, not in this module.

If a model is missing a field or fails to decode a response, [open an issue](https://github.com/ainame/swift-slack/issues) with the payload you received.
