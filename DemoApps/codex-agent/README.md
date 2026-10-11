# Codex Agent for Slack

A Slack [agent](https://docs.slack.dev/ai/agents) built with swift-slack. It answers direct messages and mentions with [Codex](https://github.com/openai/codex), through [swift-codex](https://github.com/ainame/swift-codex), and streams each reply into its thread as Codex works.

It follows the agent response loop from [Developing an agent](https://docs.slack.dev/ai/developing-agents):

- **Suggested prompts**: when someone opens the Messages tab (`app_home_opened` with `tab: "messages"`), it sets prompts with `assistant.threads.setSuggestedPrompts`.
- **Sessions**: each thread is an agent session. It calls `agents.sessions.setStatus` with `processing` and a title taken from the first message, and `chat.stopStream` returns the session to `active`.
- **Streaming**: commands, web searches, file edits, and tool calls appear as task cards (`task_update` chunks in `timeline` mode). The answer streams as `markdown_text` chunks through `chat.startStream`, `chat.appendStream`, and `chat.stopStream`.
- **Stop button**: subscribing to `agent_session_stopped` makes Slack show a stop button while the session is processing. Pressing it interrupts the Codex turn and closes the message with "_Stopped._".
- **Renaming**: after `agent_session_title_changed`, it stops proposing titles for that session.
- **Feedback**: every reply ends with `feedback_buttons` in a `context_actions` block, and a click gets an ephemeral reply.

## Streaming with AsyncStream

The `SlackStreaming` target is a layer over the streaming methods built around Swift concurrency. It depends only on swift-slack, so it can move into the library later. A producer yields chunks into an `AsyncStream` as they come, for example one chunk per token, and `ChatStream` sends them:

```swift
let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
let producer = Task {
    for try await event in agent.events(for: prompt) {
        continuation.yield(.markdownText(event.text))
    }
    continuation.finish()
}

let transport = SlackChatStreamTransport(
    client: client,
    channel: channel,
    threadTs: threadTs,
    recipientUserId: userId,
    recipientTeamId: teamId,
)
try await ChatStream(transport: transport).send(chunks, blocks: feedbackBlocks)
```

- `StreamChunk` encodes the `markdown_text`, `task_update`, and `plan_update` chunks. swift-slack types `chunks` as an untyped array because slack-api-ref declares it without an item schema.
- `ChatStream.send` starts the message with the first chunks. It collects whatever arrives while a request is in flight, merges adjacent markdown, and sends the result with the next `chat.appendStream` call, at most once per `minimumInterval` (1 second by default; the method is Tier 4). Once the stream finishes, the remaining chunks and the blocks go out with `chat.stopStream`.
- Cancelling the task that calls `send` stops the message too. To stop on request, cancel the producer instead, as `AgentResponder` does for the stop button. The producer then finishes the stream, and `send` closes the message normally.
- `ChatStreamTransport` separates the three Web API calls from the timing logic, so the tests run against a fake transport.

## Setup

### 1. Create the Slack app

Agent features require a paid plan or a [Developer Program](https://api.slack.com/developer-program) sandbox. Create an app [from this manifest](https://api.slack.com/apps):

```yaml
display_information:
  name: Codex Agent
features:
  agent_view:
    agent_description: Ask Codex about the code in its workspace.
  app_home:
    home_tab_enabled: false
    messages_tab_enabled: true
    messages_tab_read_only_enabled: false
  bot_user:
    display_name: Codex Agent
    always_online: true
oauth_config:
  scopes:
    bot:
      - app_mentions:read
      - assistant:write
      - chat:write
      - im:history
      - im:read
      - im:write
settings:
  event_subscriptions:
    bot_events:
      - agent_session_stopped
      - agent_session_title_changed
      - app_home_opened
      - app_mention
      - message.im
  interactivity:
    is_enabled: true
  org_deploy_enabled: false
  socket_mode_enabled: true
```

Install the app, create an app-level token with the `connections:write` scope, and copy the bot token (`xoxb-...`) and the app-level token (`xapp-...`).

### 2. Install Codex

```bash
brew install --cask codex
codex login
```

The agent runs Codex with a read-only sandbox and never asks for approval, in the directory set by `CODEX_WORKSPACE`, which defaults to the current directory. Each Slack session runs its own `codex app-server` process until the app exits.

### 3. Configure and run

```bash
cd DemoApps/codex-agent
cp .env.example .env   # then fill in the tokens
swift run codex-agent
```

To try the Slack side without Codex, set `AGENT_BACKEND=mock` to replay a scripted turn.

To use the Hummingbird HTTP adapter instead of Socket Mode, set `SLACK_SIGNING_SECRET`, point the manifest's request URLs at the server, and run `swift run --traits HummingbirdHTTPAdapter codex-agent`.

## Layout

- `Sources/SlackStreaming`: the AsyncStream layer (`ChatStream`, `ChunkBuffer`, `StreamChunk`, `ChatStreamTransport`), plus a `checked(_:)` helper because swift-slack does not throw for `"ok": false` responses
- `Sources/CodexAgent/App.swift`: configuration and event routing
- `Sources/CodexAgent/AgentResponder.swift`: the response loop for one message, and the stop button
- `Sources/CodexAgent/CodexBackend.swift`: one Codex thread per session, with notifications mapped to tasks and text
- `Sources/CodexAgent/MockBackend.swift`: a scripted backend for trying the app without Codex
- `Sources/CodexAgent/Feedback.swift`: the feedback buttons and their action handler

Run the tests with `swift test`.
