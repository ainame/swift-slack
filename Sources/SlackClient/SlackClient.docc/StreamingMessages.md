# Streaming messages

Send text, task updates, and Block Kit parts into a message as an asynchronous producer makes them available.

## Overview

Use ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)`` on your Slack client, or ``APIProtocol/makeStreamingMessage(channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:)`` when your app must stop the message from outside, as described in <doc:StreamingMessages#End-a-reply-that-Slack-has-already-stopped>. Both read any `AsyncSequence` whose element is ``StreamingMessage/Part``; the sequence need not be `Sendable`. Enable the `WebAPI_Chat` package trait to make this API available (see <doc:Traits>).

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

The inner group races production against the stop signal. Finishing that signal cancels only production, letting it yield a stopped notice and finish the sequence while `streamMessage` drains the remaining parts and attaches feedback blocks. Do not cancel the task that calls `streamMessage` for this: that discards the notice and the blocks, as described in <doc:StreamingMessages#Completion-errors-and-cancellation>. The outer group waits for producer cleanup before returning, including when delivery fails or the caller is cancelled. Remove the registered stop control after the outer group returns; keep a session busy until then.

This is a graceful local stop: the message is still in Slack's streaming state, so the closing calls can post the notice and blocks. When Slack has already ended the stream, use ``StreamingMessage/SessionStopped`` instead, as described in the next section.

This example assumes the values captured by the producer, including `llm`, are `Sendable`. Create the token sequence inside the child task; the sequence itself need not be `Sendable`. To read a sequence in the caller's actor isolation, pass a sequence whose type is not `Sendable`, as described in <doc:StreamingMessages#Delivery-failures-while-input-is-idle>. If the producer uses a throwing sequence, handle its error and cancellation and always finish the continuation.

### End a reply that Slack has already stopped

When your app learns that Slack has already ended the session's stream, such as from an `agent_session_stopped` event, sending more parts or a closing `chat.stopStream` serves no purpose. Create the message with ``APIProtocol/makeStreamingMessage(channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:)``, which takes the options of `streamMessage` and makes no request, register the ``StreamingMessage/Delivery`` it returns where that event's handler finds it before you await anything, and then send the parts with its `send`. The handler calls ``StreamingMessage/Delivery/notifySessionStopped()``:

```swift
let (parts, continuation) = AsyncStream.makeStream(of: StreamingMessage.Part.self)
let delivery = client.makeStreamingMessage(
    channel: channel,
    threadTs: threadTs,
    recipient: .init(userId: userId, teamId: teamId),
    blocks: feedbackBlocks,
)
// Register delivery with your agent_session_stopped handler before awaiting.
// The handler calls `await delivery.notifySessionStopped()`.

do {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            defer { continuation.finish() }
            for await token in llm.tokens(for: prompt) {
                continuation.yield(.markdown(token))
            }
        }
        // Delivery ending also cancels production; the group waits for it before returning.
        defer { group.cancelAll() }

        try await delivery.send(parts)
    }
} catch is StreamingMessage.SessionStopped {
    // Slack ended the reply. No ts is returned; delivery.messageTs has it if the message was started.
}
```

`send` behaves like `streamMessage`, which is a shorthand for creating a delivery and sending it, and has the same two overloads; the sections below apply to both. Once the message's delivery observes the stop, `send` discards the parts and closing blocks it has not sent, starts no further call or retry, and stops waiting for `minimumInterval` or a `Retry-After` delay. A request that has already passed the stop check may still begin and cannot be withdrawn: `send` waits for it without cancelling it, ignores its result or error, and then throws ``StreamingMessage/SessionStopped``. This holds whatever the input is doing, including after it has finished while the closing calls or their `Retry-After` waits remain.

`send` throws only once it is done reading the input. It reads a `Sendable` input, such as this `AsyncStream`, in a child task that it cancels, so an input that honors cancellation ends even while it waits for an element; throwing then cancels production in the example's task group. An input read in the caller's isolation, as described in <doc:StreamingMessages#Delivery-failures-while-input-is-idle>, cannot be interrupted: `send` throws when that input yields its next element or ends, so end it, and stop its producer, from the same handler.

A delivery sends one message. Its first `send` reserves it before reading the input or calling Slack and holds it until it returns or throws, so its ``StreamingMessage/Delivery/state`` goes from `ready` to `streaming` to `ended`. Any other `send` on it, at the same time or later, throws ``StreamingMessage/Delivery/AlreadyUsed`` without reading its input or calling Slack, and leaves the message alone. A stop marked before `send` is kept: `send` then posts nothing and throws ``StreamingMessage/SessionStopped``. A stop marked after `send` has ended has no effect.

``StreamingMessage/Delivery/messageTs`` holds the message's timestamp as soon as `chat.startStream` succeeds, including a start made with the closing calls. It stays set when a later call fails or Slack ends the session, when `send` throws instead of returning the timestamp.

With `streamMessage`, which has no delivery to mark, end the input by throwing ``StreamingMessage/SessionStopped`` from it, for example with `continuation.finish(throwing: StreamingMessage.SessionStopped())` on an `AsyncThrowingStream`, and stop your producer yourself. That has the same effect, but only when `streamMessage` reads it from the sequence, after any parts yielded before it; once the input has finished, it can no longer end the closing calls or their retries.

Ending the input with any other error is not this signal: it still sends the parts collected so far and stops the message. Cancelling the task that calls `streamMessage` is not this signal either: it discards unsent parts but still attempts a stop, as described below. Once `streamMessage` reads the signal, even while that attempt is in progress, it throws ``StreamingMessage/SessionStopped`` rather than the cancellation.

Task updates with the same `id` update an existing task. The default `taskDisplay: .timeline` shows task cards between surrounding text. Use `.plan` and `.plan(title:)` parts to show tasks together in a plan. Task updates can also include details, output, and source links.

A `.blocks` part travels in order with other parts. The separate `blocks:` parameter supplies up to 50 blocks at the bottom of the finished message, such as feedback controls.

### Completion, errors, and cancellation

When the sequence finishes, buffered parts and the closing `blocks` go out with `chat.stopStream`. `sessionStatus:` can set the final agent session status; Slack defaults it to `active`.

If the input throws, buffered parts and closing blocks are sent before the input error is rethrown, unless the error is ``StreamingMessage/SessionStopped`` (see <doc:StreamingMessages#End-a-reply-that-Slack-has-already-stopped>). If it throws before producing anything, no message is posted. To end a reply early and still deliver everything, including a closing notice and `blocks`, end the input as shown in <doc:StreamingMessages#Produce-tasks-text-and-blocks>. Only the end of the input decides this: an input that throws `CancellationError` while the task calling `streamMessage` is not cancelled ends gracefully like any other error.

A failed Slack call, including a closing `chat.startStream` or `chat.stopStream`, triggers a best-effort stop without additional chunks or blocks once the message has a `ts`, then rethrows the error, even when that stop fails too. Its parts are not resent: a call that fails in flight, such as on a dropped connection, may already have reached Slack. Slack responses with `"ok": false` throw ``StreamingMessage/Error``, containing the method and error code. The best-effort stop is a single attempt: it is not retried when Slack rate limits it.

Cancelling the task that calls `streamMessage` ends delivery without a final flush:

- Parts not yet sent and the closing `blocks` are discarded.
- Requests run in the calling task and honor its cancellation. A request in progress may already have reached Slack, so its outcome is unknown and its parts are not resent. A call that waits out a `Retry-After` delay is not retried.
- When the message has a `ts`, `streamMessage` attempts one `chat.stopStream` without content protected from cancellation, and does not retry it or wait out a `Retry-After` delay for it. When a start completes before the cancellation is noticed, its `ts` is kept for that stop.
- When the cancellation interrupts the first `chat.startStream`, Slack may have posted a message whose `ts` is unknown. No stop is possible, and that message can stay in Slack's streaming state.
- `streamMessage` then rethrows the error of the call the cancellation interrupted, or the error the input ended with if delivery has already read it, and otherwise throws `CancellationError`. ``StreamingMessage/SessionStopped`` takes precedence, and no stop is attempted after it.

The cancellation also wakes delivery if it is waiting for parts. Cancellation handlers run synchronously, so this wake-up happens in a short-lived task that makes no request and that `streamMessage` does not await.

Cancellation does not guarantee a prompt return or a successful stop. `streamMessage` returns only once it has finished reading the input, and an input that ignores cancellation keeps it waiting (see <doc:StreamingMessages#Delivery-failures-while-input-is-idle>). When a stop call or the best-effort stop fails, or a cancelled start leaves the `ts` unknown, the message can stay in Slack's streaming state.

### Batching and rate limits

The library starts with `chat.startStream`, appends with `chat.appendStream`, and closes with `chat.stopStream`. It collects parts while calls are in flight, merging adjacent markdown up to 12,000 characters per chunk and adjacent blocks up to 50 per chunk. Parts of different kinds preserve their order.

`minimumInterval:` defaults to one second between streaming calls. HTTP 429 responses wait for `Retry-After` and retry, up to three attempts per call, unless the task is cancelled. Closing calls run as soon as the final buffered batch is available.

### Delivery failures while input is idle

`streamMessage` and a delivery's `send` each have two overloads, and Swift picks one from the argument's static type. A `Sendable` input, including `AsyncStream`, `AsyncThrowingStream`, and an `AsyncStream` mapped directly with `map`, is read in a child task concurrently with delivery. A failed Slack call, or a session stop through a ``StreamingMessage/Delivery``, cancels iteration immediately, so apps can stop an idle producer or pending question without waiting for another token. The input must cooperate with cancellation: `streamMessage` returns only once iteration ends.

Any other input, including one in generic code whose type is constrained only to `AsyncSequence`, is read in the caller's actor isolation, even when its concrete type is `Sendable`. Reading and delivery then share the calling task, so a failed Slack call is noticed only when the input yields its next element or ends. A session stop through a delivery still ends delivery at once, but `send` throws only then too: while the input is idle, `streamMessage` neither returns nor cancels it. End such an input yourself, for example from the same code that stops its producer, or pass a `Sendable` input when delivery failures must end an idle input.

Cancelling the task that calls `streamMessage` reaches the input on both paths, because the input is read in that task or its child. An input such as `AsyncStream` then either ends or throws, and both are handled as the cancellation. Delivery notices the cancellation and attempts its stop even while the input is idle, but an input that ignores cancellation keeps `streamMessage` from returning until it yields or ends.
