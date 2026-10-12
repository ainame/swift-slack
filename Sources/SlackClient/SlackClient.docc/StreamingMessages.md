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

An `AsyncStream` lets a producer yield different kinds of parts. Run production in a structured child scope. To let your app stop a reply early and still finish it, use a separate stop signal, such as one your app's own stop control finishes; it cancels production while delivery finishes the message:

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

This is a graceful local stop: the message is still in Slack's streaming state, so the closing calls can post the notice and blocks. When Slack has already ended the stream, use ``StreamingMessage/SessionStopped`` instead, as described in the next section.

This example assumes the values captured by the producer, including `llm`, are `Sendable`. Create the token sequence inside the child task; the sequence itself need not be `Sendable`. To read a sequence in the caller's actor isolation, use the direct mapping example above. If the producer uses a throwing sequence, handle its error and cancellation and always finish the continuation.

### End a reply that Slack has already stopped

When your app learns that Slack has already ended the session's stream, sending more parts or a closing `chat.stopStream` serves no purpose. End the input by throwing ``StreamingMessage/SessionStopped`` from it, and stop your producer yourself; `streamMessage` reads the sequence but does not control what feeds it:

```swift
let (parts, continuation) = AsyncThrowingStream.makeStream(of: StreamingMessage.Part.self)
let (sessionEnds, sessionEndContinuation) = AsyncStream.makeStream(of: Void.self)
// Register sessionEndContinuation with the code that learns Slack has ended the stream.
// That code calls sessionEndContinuation.finish().

do {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            await withTaskGroup(of: Void.self) { production in
                production.addTask {
                    for await token in llm.tokens(for: prompt) {
                        continuation.yield(.markdown(token))
                    }
                    continuation.finish()
                }
                production.addTask {
                    for await _ in sessionEnds {}
                    // Cancellation also ends the wait; only the signal ends the input this way.
                    if !Task.isCancelled {
                        continuation.finish(throwing: StreamingMessage.SessionStopped())
                    }
                }
                // Whichever ends first cancels the other, so the signal also stops the producer.
                _ = await production.next()
                production.cancelAll()
            }
            // Ends the input if production was cancelled before it finished; otherwise has no effect.
            continuation.finish()
        }
        // Delivery ending also cancels production; the group waits for it before returning.
        defer { group.cancelAll() }

        try await client.streamMessage(
            parts,
            channel: channel,
            threadTs: threadTs,
            recipient: .init(userId: userId, teamId: teamId),
            blocks: feedbackBlocks,
        )
    }
} catch is StreamingMessage.SessionStopped {
    // Slack ended the reply. No ts is returned, and no call was started after the signal was read.
}
```

Once `streamMessage` reads the signal, it discards the parts and closing blocks it has not sent, starts no further call, including retries and the closing `chat.stopStream`, and stops waiting for `minimumInterval` or a `Retry-After` delay. A call already in progress cannot be withdrawn: `streamMessage` waits for it without cancelling it, ignores its result or error, and then throws ``StreamingMessage/SessionStopped``. The signal takes effect when `streamMessage` reads it from the sequence, after any parts yielded before it.

Cancelling the task that calls `streamMessage`, or ending the input with any other error, is not this signal: those still send the parts collected so far and stop the message, as described below.

Task updates with the same `id` update an existing task. The default `taskDisplay: .timeline` shows task cards between surrounding text. Use `.plan` and `.plan(title:)` parts to show tasks together in a plan. Task updates can also include details, output, and source links.

A `.blocks` part travels in order with other parts. The separate `blocks:` parameter supplies up to 50 blocks at the bottom of the finished message, such as feedback controls.

### Completion, errors, and cancellation

When the sequence finishes, buffered parts and the closing `blocks` go out with `chat.stopStream`. `sessionStatus:` can set the final agent session status; Slack defaults it to `active`.

If the input throws, buffered parts and closing blocks are sent before the input error is rethrown, unless the error is ``StreamingMessage/SessionStopped`` (see <doc:StreamingMessages#End-a-reply-that-Slack-has-already-stopped>). If it throws before producing anything, no message is posted. Cancelling the task that calls `streamMessage` also sends the parts collected so far and closes the message. Closing calls run in a task that does not inherit cancellation. If the cancellation comes while a call waits out a `Retry-After` delay, that call is not retried in the cancelled task; Slack rejected it without processing it, so its parts go out with the closing calls, which wait for the rest of the delay first.

A failed Slack call triggers a best-effort stop without additional chunks or blocks, then rethrows the error. Its parts are not resent: unlike a rate-limited rejection, a call that fails in flight, such as on a dropped connection, may already have reached Slack. Slack responses with `"ok": false` throw ``StreamingMessage/Error``, containing the method and error code. A failed closing request can still prevent Slack from completing the message.

### Batching and rate limits

The library starts with `chat.startStream`, appends with `chat.appendStream`, and closes with `chat.stopStream`. It collects parts while calls are in flight, merging adjacent markdown up to 12,000 characters per chunk and adjacent blocks up to 50 per chunk. Parts of different kinds preserve their order.

`minimumInterval:` defaults to one second between streaming calls. HTTP 429 responses wait for `Retry-After` and retry, up to three attempts per call. Closing calls run as soon as the final buffered batch is available.
