# Codex Agent for Slack

A Slack [agent](https://docs.slack.dev/ai/agents) built with swift-slack. It answers direct messages, mentions, and messages in Slack Code channels with [Codex](https://github.com/openai/codex), through [swift-codex](https://github.com/ainame/swift-codex), and streams each reply as Codex works.

In DMs and other channels, each thread is one conversation. Reply in the thread to continue it: in DMs and in channel threads the agent has joined, replies need no mention. In a Slack Code channel, the whole channel is one conversation: every message in it, top-level or in a thread, continues it.

It follows the agent response loop from [Developing an agent](https://docs.slack.dev/ai/developing-agents):

- **Suggested prompts**: when someone opens the Messages tab (`app_home_opened` with `tab: "messages"`), it sets prompts with `assistant.threads.setSuggestedPrompts`.
- **Threads**: replies in a channel thread the agent has answered in reach it through `message.channels` and `message.groups`. Replies that mention it are left to `app_mention`. After a restart, `conversations.replies` shows whether the bot has posted in the thread. When the agent joins a thread it has not seen, such as on a mention partway through a discussion or after a restart, the prompt starts with the thread so far.
- **Code channels**: a channel whose `conversations.info` reports `properties.record_channel.record_type` as `agent_channel` is a Slack Code channel. Every person's message there is a turn, without a mention, from anyone `ALLOWED_USER_IDS` allows. A top-level message gets a top-level reply, and a thread reply gets a reply in its thread, but both belong to the channel's one session. Channels created by the app or already handled as Code channels keep that identity even if a later lookup fails. The lookup is cached: for good for a code channel, for 10 minutes for another channel, and not at all when it fails, so the next message tries again. The first prompt in a code channel starts with the channel's recent messages, oldest first, and the message the channel was started from when Slack reports one.
- **Sessions**: each DM or channel thread is an agent session, and so is each code channel. It calls `agents.sessions.setStatus` with `processing` and a title taken from the first message, without `thread_ts` for a code channel, and `chat.stopStream` returns the session to `active`. A session answers one message at a time; a message that arrives meanwhile gets an ephemeral busy notice, which in a code channel can come from someone else's turn.
- **One turn per message**: a message that mentions the bot arrives both as `message` and as `app_mention`, and Slack retries events it thinks were lost. The app remembers recent event IDs and message timestamps, so each message starts at most one turn, and it ignores its own and other bots' messages. Event handlers return at once and route the message in a task, because in HTTP mode Slack retries an event whose request takes longer than three seconds.
- **Streaming**: commands, web searches, file edits, and tool calls appear as task cards (`task_update` chunks in `timeline` mode). The answer streams as `markdown_text` chunks through `chat.startStream`, `chat.appendStream`, and `chat.stopStream`.
- **Stop button**: subscribing to `agent_session_stopped` makes Slack show a stop button while the session is processing. Slack ends the session and its streaming message itself, so the agent ends the reply's input with `StreamingMessage.SessionStopped`: `streamMessage` drops what it has not sent and makes no further call. The agent then interrupts the Codex turn and ends a question waiting for a click, and calls Slack no more for that turn: no stopped notice, status change, question update, or rename. An event without `thread_ts` stops every turn in its channel, including thread sessions; one with `thread_ts` stops that thread's session, or the code channel turn replying in that thread. Messages and card questions still being routed there, such as one waiting for its channel lookup, are discarded too; messages sent after the stop start turns as usual.
- **Renaming**: after `agent_session_title_changed`, it stops proposing titles for that session, which is the code channel's when the event has no `thread_ts`.
- **Tools**: Codex can rename the session, read the conversation, and ask the person to choose, through tools that act in Slack. See below.
- **Cards**: Codex can call a `show_cards` tool, and the answer ends with cards or a carousel with Open and "Ask about this" buttons. See below.
- **Feedback**: every reply ends with `feedback_buttons` in a `context_actions` block, and a click gets an ephemeral reply.

## Cards from the agent's answer

The agent never writes Block Kit. The codex backend registers a `show_cards` tool with Codex, using swift-codex's experimental client-defined tools (`ThreadOptions.dynamicTools`). Each card has an optional title, subtitle, body, `https` link, and follow-up question, and Codex calls the tool when a few items deserve to stand out:

```json
{"cards": [{"title": "Agent sessions", "body": "How Slack shows the stop button.", "url": "https://docs.slack.dev/ai/agent-sessions", "ask": "How does the stop button work?"}]}
```

- `AgentToolset.handle` only checks the arguments of `show_cards`. Invalid ones get `success: false` with a message, so Codex can retry. The handler must not wait on another request to the same app server.
- The cards are read from the completed `dynamicToolCall` item and stream nothing. When the answer is done, `SlackUI` turns them into a `card`, or a `carousel` for two to ten cards, within the card block's limits (150 characters for titles and subtitles, 200 for bodies).
- The app decides the buttons: Open for an `https` link, and "Ask about this", which posts the question in the thread and answers it. The model cannot add other actions or links.
- When the answer finishes, the producer yields the cards as a `StreamingMessage.Part.blocks` chunk. Feedback buttons are passed separately to `streamMessage` as the closing message's `blocks`.
- Tools are registered when a Codex thread starts. A thread resumed after an idle close keeps them.

The mock backend sends two cards the same way, so `AGENT_BACKEND=mock` shows them without Codex.

## Tools that act in Slack

Besides `show_cards`, the Codex backend registers conversation and Code channel tools. Each turn gets a `SlackAgentTools` scoped to its session, the thread its reply goes into, and the person it answers, and the mock backend calls the same tools, so `AGENT_BACKEND=mock` shows them too.

| Tool | What it does |
| --- | --- |
| `set_title` | Renames the session with `agents.sessions.rename`. It refuses once the person has renamed the session (`agent_session_title_changed`). |
| `read_slack` | Returns up to 50 recent messages from the thread the reply goes into or from its channel, with `conversations.replies` or `conversations.history`. A top-level reply in a code channel has no thread, so it reads the channel. It cannot read other conversations. |
| `start_code_channel` | Offered in ordinary conversations to create or reuse a Code channel for editing, implementation, tests or substantial coding work, preserves the origin link, registers `/review` and `/run`, and starts the original task there once. The agent decides when to call it; there is no keyword heuristic. Inside a Code channel it works on the task directly, without this tool. Rename and channel-decoration failures do not trigger another handoff. |
| `publish_code_view` | Publishes HTML, unified diff, Block Kit, an existing Canvas or a PR URL in the current Code channel. Stable keys update the same artifact. Codex diff notifications also update the channel's diff view automatically. |
| `archive_code_channel` | Posts and attaches a summary, shares it back to the origin thread when linked, then archives the channel and stops the turn. The tool is reserved for a person's request to end the task. |
| `ask_user` | Posts the question where the reply goes, with a button per option, sets the session to `suspended`, and returns the option the person picks. Only that person can answer; the question expires after 10 minutes. |

Tool calls appear as task cards, and failures go back to Codex as messages it can act on. swift-codex runs a tool handler while it reads the app-server's messages, so a waiting `ask_user` holds every other message, including the reply to an interrupt. The stop button therefore ends the question before it interrupts the turn.

## Streaming with AsyncSequence

The library's `client.streamMessage` takes any `AsyncSequence` of `StreamingMessage.Part`. The demo uses an `AsyncThrowingStream` and a demo-local `TurnProducer` stop control. Production runs in a structured child scope, so a stop can cancel it independently of Slack delivery:

```swift
let (parts, continuation) = AsyncThrowingStream.makeStream(of: StreamingMessage.Part.self)
let producer = TurnProducer()
// Register both before awaiting. When Slack stops the session, the stop handler calls
// continuation.finish(throwing: StreamingMessage.SessionStopped()) and then producer.stopSession().
await withTaskGroup(of: Void.self) { group in
    group.addTask {
        await producer.run {
            defer { continuation.finish() }
            for await text in agent.tokens(for: prompt) {
                continuation.yield(.markdown(text))
            }
        }
    }
    defer { group.cancelAll() }

    do {
        try await client.streamMessage(
            parts,
            channel: channel,
            threadTs: replyThreadTs, // nil for a top-level reply in a code channel
            recipient: .init(userId: userId, teamId: teamId),
            blocks: feedbackBlocks,
        )
    } catch is StreamingMessage.SessionStopped {
        // Slack ended the session: make no more calls for this turn.
    } catch {
        producer.cancel()
        // Then set the session back to `active`, which a failed delivery leaves `processing`.
    }
}
```

- `TurnProducer.run` races production against a stop signal and cancels the remaining child. The enclosing group waits for producer cleanup before the demo clears the busy session, including when delivery fails or Slack stops the session.
- `TurnProducer` records why production stopped. `cancel()` is the app's own graceful stop: the message is still streaming, so the producer can yield a stopped notice and `streamMessage` finishes the message. `stopSession()` records that Slack ended the session, which the tools check before every Slack call.
- Parts include `.markdown`, `.task`, `.plan(title:)`, and `.blocks`. Blocks are streamed in order with other parts; the `blocks:` argument adds blocks at the bottom of the finished message.
- `streamMessage` collects parts while requests are in flight, merges adjacent markdown up to 12,000 characters and blocks up to 50, and spaces calls by `minimumInterval` (1 second by default).
- Finishing the input sends remaining parts and closing blocks with `chat.stopStream`. Ending it with `StreamingMessage.SessionStopped` discards them and starts no further call. Cancelling the task calling `streamMessage` also closes the message, using a task that does not inherit cancellation.
- If the input throws, buffered parts and closing blocks are sent before the error is rethrown. If a Slack call fails, the message is stopped without additional chunks or blocks before rethrowing. HTTP 429 responses are retried after `Retry-After`, up to three attempts.
- The library's streaming tests use fake transports and HTTP responses. The API requires the `WebAPI_Chat` trait, enabled by this demo.

## Setup

### 1. Create the Slack app

Agent features require a paid plan or a [Developer Program](https://api.slack.com/developer-program) sandbox. Create an app [from this manifest](https://api.slack.com/apps):

```yaml
display_information:
  name: Codex Agent
features:
  code_channels:
    enabled: true
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
      - channels:history
      - channels:read
      - chat:write
      - code_channels:manage
      - groups:history
      - groups:read
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
      - message.channels
      - message.groups
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

The agent runs Codex with a read-only sandbox by default. Set `CODEX_WORKSPACE` to a repository to ask about it; otherwise Codex works in an empty temporary directory and answers general questions. Each Slack session, a thread or a code channel, runs its own Codex thread in its own `codex app-server` process, because swift-codex allows one active turn per process. A session idle for 10 minutes closes its process, and its next message resumes the Codex thread in a new one. A stopped turn is interrupted and read to its end before the session's next turn starts.

To enable coding, set both `CODEX_WORKSPACE` (a local Git repository) and `CODEX_SESSION_WORKSPACES` (a separate directory outside that repository). Only Code channel sessions become writable. Each gets an independent clone of committed content, with no hardlinks or shared Git directory. The local source remote is removed, so pushes do not target the developer's checkout; configure a publishing remote explicitly when needed. The original checkout and uncommitted changes are preserved. Checkouts remain on disk for inspection, and idle Codex processes resume in their existing checkout. After an app restart, new checkouts are allocated; conversation IDs and workspaces are not persisted across app restarts.

Writable sessions use Codex's Auto configuration: the `workspace-write` sandbox and `on-request` approval policy. Codex can run ordinary commands and edit files inside its checkout automatically; operations requiring additional permissions may still ask for approval. Both command and file-change approval requests are shown as Slack buttons to the requesting person. Outside-checkout working directories and grant roots are refused; absent handlers, timeout, cancellation and session stop deny requests. The source repository should contain only material the agent is allowed to read: tracked `.env` files and escaping symlinks cause allocation to fail.

The generated manifest model does not represent `features.code_channels`, so configure this YAML directly and reinstall the app for its new scope. In HTTP mode add `features.code_channels.slash_command_url` alongside the request URLs. Code channel `info` context items are used; `code_channel_action` has no upstream java-slack-sdk model and is not handled. Generated readback also omits views, summary messages and item types. Canvas publication uses an existing canvas ID.

### 3. Decide who can use it

> [!WARNING]
> The read-only sandbox stops Codex from writing files, not from reading them. Codex can read anything your user account can, such as `~/.ssh` or another project's `.env`, and whatever it reads can end up in a Slack reply. Run the agent only for people you trust with that access.

The demo limits that exposure:

- `ALLOWED_USER_IDS` optionally lists the Slack user IDs the agent answers, comma-separated, and other people get an ephemeral notice. Without it the agent answers everyone and logs a warning at startup; set it when other people share the workspace.
- The app refuses a `CODEX_WORKSPACE` that contains the app's `.env` file or has a `.env` file of its own, and uses an empty directory when it is not set. If you supply tokens through environment variables and no `.env` file exists, the workspace can contain the app's directory.
- Codex starts with only the variables it needs (`PATH`, `HOME`, locale, and `CODEX_HOME`), so exported Slack tokens do not reach it.

Messages from anyone in a thread the agent joins, or in a code channel, can still go into its prompt as context, so treat what they write as untrusted input.

### 4. Configure and run

```bash
cd DemoApps/codex-agent
cp .env.example .env   # then fill in the tokens
swift run codex-agent
```

To try the Slack side without Codex, set `AGENT_BACKEND=mock` to replay a scripted turn.

To use the Hummingbird HTTP adapter instead of Socket Mode, set `SLACK_SIGNING_SECRET`, point the manifest's request URLs at the server, and run `swift run --traits HummingbirdHTTPAdapter codex-agent`.

## Layout

- `Sources/CodexAgent/SlackResponse.swift`: the demo's `checked(_:)` helper for non-streaming Web API responses with `"ok": false`; streaming uses the library's `StreamingMessage.Error`
- `Sources/CodexAgent/App.swift`: configuration and event handlers
- `Sources/CodexAgent/TurnRouter.swift`: which messages become turns, in which session, and where the reply goes; code channel detection and duplicate filtering
- `Sources/CodexAgent/AgentResponder.swift`: the response loop for one message, busy sessions, and the stop button
- `Sources/CodexAgent/TurnProducer.swift`: the stop control for a turn's producer, telling a local cancellation from a session Slack stopped
- `Sources/CodexAgent/ConversationHistory.swift`: reading a thread or a code channel for the prompt and the tools
- `Sources/CodexAgent/CodeChannelLifecycle.swift`: channel creation, idempotency and initial properties/commands
- `Sources/CodexAgent/SessionWorkspaces.swift`: independent writable checkouts
- `Sources/CodexAgent/CodeTools.swift`: Code channel tool schemas and typed view arguments
- `Sources/CodexAgent/CodexBackend.swift`: one Codex thread per session, with notifications mapped to tasks and text
- `Sources/CodexAgent/MockBackend.swift`: a scripted backend for trying the app without Codex
- `Sources/CodexAgent/Feedback.swift`: the feedback buttons and their action handler
- `Sources/CodexAgent/SlackUI.swift`: the card vocabulary and its conversion to Block Kit
- `Sources/CodexAgent/SlackAgentTools.swift`: the tools' Slack side, and the questions waiting for a click; `AgentToolset` in `CodexBackend.swift` registers the tools with Codex

Run the tests with `swift test`.
