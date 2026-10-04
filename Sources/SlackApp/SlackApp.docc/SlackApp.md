# ``SlackApp``

Build Slack apps that respond to events, commands, and interactions.

## Overview

`SlackApp` is the app runtime of the `swift-slack` package, built on `SlackClient`. It receives requests from Slack over Socket Mode or signed HTTP, acknowledges them, and dispatches them to the handlers you register on a ``Router``.

In app code, `import SlackKit`, which re-exports this module along with `SlackClient` and `SlackBlockKit`. Import `SlackApp` directly only when you want the runtime without the umbrella module.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Examples>
- <doc:MigrationGuide>

### Running an App

- ``SlackApp/SlackApp``
- ``Router``

### Handling Requests

- ``SlackApp/SlackApp/Context``
- ``SlackApp/SlackApp/EventContext``
- ``Ack``
- ``Say``
- ``Respond``

### HTTP Integration

- ``HTTPServerAdapter``
- ``HTTPServerHandler``
