# Streaming messages

Send text, task updates, and Block Kit parts into a thread as an asynchronous producer makes them available.

## Overview

Use ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)`` on your Slack client. It reads any `AsyncSequence` whose element is ``StreamingMessage/Part``; the sequence need not be `Sendable`. Enable the `WebAPI_Chat` package trait to make this API available (see <doc:Traits>).

### Stream an LLM's tokens

Map a sequence of text deltas into markdown parts:

```swift
let parts = llm.tokens(for: prompt).map { StreamingMessage.Part.markdown($0) }
let ts = try await client.streamMessage(
    parts,
    channel: channel,
    threadTs: threadTs,
    recipient: .init(userId: userId, teamId: teamId),
)
```

The return value is the reply's message timestamp. Supply `recipient` when replying in a channel; it identifies the user and their workspace.

### Produce tasks, text, and blocks

An `AsyncStream` lets a producer yield different kinds of parts. Keep its task handle to implement a stop button:

```swift
let (parts, continuation) = AsyncStream.makeStream(of: StreamingMessage.Part.self)
let producer = Task {
    defer { continuation.finish() }
    continuation.yield(.task(.init(
        id: "search",
        title: "Searching documentation",
        status: .inProgress,
    )))
    for await token in llm.tokens(for: prompt) {
        continuation.yield(.markdown(token))
    }
    if Task.isCancelled {
        continuation.yield(.markdown("\n\n_Stopped._"))
    } else {
        continuation.yield(.task(.init(
            id: "search",
            title: "Searching documentation",
            status: .complete,
        )))
        continuation.yield(.blocks(resultBlocks))
    }
}

// A stop-button handler calls producer.cancel().
try await client.streamMessage(
    parts,
    channel: channel,
    threadTs: threadTs,
    recipient: .init(userId: userId, teamId: teamId),
    blocks: feedbackBlocks,
)
```

Cancelling the producer lets it yield a stopped notice and finish the sequence. If the producer uses a throwing sequence, handle its error and cancellation and always finish the continuation. If `streamMessage` throws, cancel any producer task you created so it does not keep working.

Task updates with the same `id` update an existing task. The default `taskDisplay: .timeline` shows task cards between surrounding text. Use `.plan` and `.plan(title:)` parts to show tasks together in a plan. Task updates can also include details, output, and source links.

A `.blocks` part travels in order with other parts. The separate `blocks:` parameter supplies up to 50 blocks at the bottom of the finished message, such as feedback controls.

### Completion, errors, and cancellation

When the sequence finishes, buffered parts and the closing `blocks` go out with `chat.stopStream`. `sessionStatus:` can set the final agent session status; Slack defaults it to `active`.

If the input throws, buffered parts and closing blocks are sent before the input error is rethrown. If it throws before producing anything, no message is posted. Cancelling the task that calls `streamMessage` also sends the parts collected so far and closes the message. Closing calls run in a task that does not inherit cancellation.

A failed Slack call triggers a best-effort stop without additional chunks or blocks, then rethrows the error. Slack responses with `"ok": false` throw ``StreamingMessage/Error``, containing the method and error code. A failed closing request can still prevent Slack from completing the message.

### Batching and rate limits

The library starts with `chat.startStream`, appends with `chat.appendStream`, and closes with `chat.stopStream`. It collects parts while calls are in flight, merging adjacent markdown up to 12,000 characters per chunk and adjacent blocks up to 50 per chunk. Parts of different kinds preserve their order.

`minimumInterval:` defaults to one second between streaming calls. HTTP 429 responses wait for `Retry-After` and retry, up to three attempts per call. Closing calls run as soon as the final buffered batch is available.
