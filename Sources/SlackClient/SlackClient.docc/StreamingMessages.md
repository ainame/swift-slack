# Streaming messages

Send text, task updates, and Block Kit parts into a message as an asynchronous producer makes them available.

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

### Stream a top-level message

Omit `threadTs` to stream a top-level message instead of a thread reply. The request then leaves out `thread_ts`. Slack supports this only in channels where the whole channel is one agent session, such as Slack Code; elsewhere `chat.startStream` fails with `invalid_thread_ts`, which throws ``StreamingMessage/Error``.

```swift
try await client.streamMessage(parts, channel: channel)
```

### Produce tasks, text, and blocks

An `AsyncStream` lets a producer yield different kinds of parts. Run production in a structured child scope, and use a separate stop signal so a stop button cancels production while Slack delivery finishes the message:

```swift
let (parts, continuation) = AsyncStream.makeStream(of: StreamingMessage.Part.self)
let (stopRequests, stopContinuation) = AsyncStream.makeStream(of: Void.self)
// Register stopContinuation with your stop-button handler before awaiting.
// The handler calls stopContinuation.finish() to request a stop.

try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        await withTaskGroup(of: Void.self) { production in
            production.addTask {
                defer { continuation.finish() }
                continuation.yield(.task(.init(
                    id: "search",
                    title: "Searching documentation",
                    status: .inProgress,
                )))
                if !Task.isCancelled {
                    for await token in llm.tokens(for: prompt) {
                        continuation.yield(.markdown(token))
                    }
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
            production.addTask {
                for await _ in stopRequests {}
            }
            // Stop cancels the producer; normal completion cancels the stop waiter.
            _ = await production.next()
            production.cancelAll()
        }
    }
    // Delivery ending also cancels production, including when a Slack call throws.
    defer { group.cancelAll() }

    try await client.streamMessage(
        parts,
        channel: channel,
        threadTs: threadTs,
        recipient: .init(userId: userId, teamId: teamId),
        blocks: feedbackBlocks,
    )
}
```

The inner group races production against the stop signal. Finishing that signal cancels only production, letting it yield a stopped notice and finish the sequence while `streamMessage` drains the remaining parts and attaches feedback blocks. The outer group waits for producer cleanup before returning, including when delivery fails or the caller is cancelled. Remove the registered stop control after the outer group returns; keep a session busy until then.

This example assumes the values captured by the producer, including `llm`, are `Sendable`. Create the token sequence inside the child task; the sequence itself need not be `Sendable`. To read a sequence in the caller's actor isolation, use the direct mapping example above. If the producer uses a throwing sequence, handle its error and cancellation and always finish the continuation.

Task updates with the same `id` update an existing task. The default `taskDisplay: .timeline` shows task cards between surrounding text. Use `.plan` and `.plan(title:)` parts to show tasks together in a plan. Task updates can also include details, output, and source links.

A `.blocks` part travels in order with other parts. The separate `blocks:` parameter supplies up to 50 blocks at the bottom of the finished message, such as feedback controls.

### Completion, errors, and cancellation

When the sequence finishes, buffered parts and the closing `blocks` go out with `chat.stopStream`. `sessionStatus:` can set the final agent session status; Slack defaults it to `active`.

If the input throws, buffered parts and closing blocks are sent before the input error is rethrown. If it throws before producing anything, no message is posted. Cancelling the task that calls `streamMessage` also sends the parts collected so far and closes the message. Closing calls run in a task that does not inherit cancellation.

A failed Slack call triggers a best-effort stop without additional chunks or blocks, then rethrows the error. Slack responses with `"ok": false` throw ``StreamingMessage/Error``, containing the method and error code. A failed closing request can still prevent Slack from completing the message.

### Batching and rate limits

The library starts with `chat.startStream`, appends with `chat.appendStream`, and closes with `chat.stopStream`. It collects parts while calls are in flight, merging adjacent markdown up to 12,000 characters per chunk and adjacent blocks up to 50 per chunk. Parts of different kinds preserve their order.

`minimumInterval:` defaults to one second between streaming calls. HTTP 429 responses wait for `Retry-After` and retry, up to three attempts per call. Closing calls run as soon as the final buffered batch is available.
