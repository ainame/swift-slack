#if WebAPI_Chat
import SlackBlockKit

extension APIProtocol {
    /// Streams `parts` into one message, and stops the message once `parts` ends.
    ///
    /// Pass any `AsyncSequence` of ``StreamingMessage/Part``, such as an LLM's text deltas mapped to
    /// ``StreamingMessage/Part/markdown(_:)``:
    ///
    /// ```swift
    /// try await context.client.streamMessage(
    ///     llm.tokens(for: prompt).map { StreamingMessage.Part.markdown($0) },
    ///     channel: event.channel,
    ///     threadTs: event.threadTs ?? event.ts,
    ///     recipient: .init(userId: event.user, teamId: envelope.teamId),
    /// )
    /// ```
    ///
    /// The method starts the message with `chat.startStream` when the first parts arrive, sends the parts that
    /// arrive during each call together with the next `chat.appendStream` call, waits at least
    /// `minimumInterval` between calls, and sends the parts left when `parts` ends with `chat.stopStream`.
    /// Adjacent markdown merges into one chunk, so a producer can yield one part per token.
    ///
    /// The message is stopped, so it never stays streaming, unless Slack has already ended it:
    ///
    /// - When `parts` finishes, the remaining parts and `blocks` go out with the stop call.
    /// - When `parts` throws, the parts so far and `blocks` go out, and then the error is rethrown.
    ///   If `parts` throws before producing anything, no message is posted.
    /// - When `parts` throws ``StreamingMessage/SessionStopped`` because Slack has already ended the session,
    ///   the parts and `blocks` not yet sent are discarded and no further call is made, not even a retry or
    ///   the stop call. A call already in progress cannot be withdrawn; the method waits for it without
    ///   cancelling it, ignores its outcome, and rethrows ``StreamingMessage/SessionStopped``.
    /// - When the calling task is cancelled, the parts so far and `blocks` go out. The closing calls run in a
    ///   task that does not inherit the cancellation.
    /// - When a call fails, the message is stopped without further content, and the error is rethrown. Slack
    ///   answering `"ok": false` throws ``StreamingMessage/Error``. Rate-limited calls (HTTP 429) are retried
    ///   after their `Retry-After` delay, up to three attempts.
    ///
    /// `parts` is read in the calling task, so it need not be `Sendable`. To stop a reply early while still
    /// finishing it, end `parts`, for example by cancelling the task that yields to an `AsyncStream`; that
    /// task can still yield closing parts, such as a note that the reply was stopped. Ending `parts`, with any
    /// error, does not stop whatever produces them; stop the producer separately.
    ///
    /// - Parameters:
    ///   - parts: The message content, in order.
    ///   - channel: The channel to post in.
    ///   - threadTs: The thread to reply in. Pass `nil` to stream a top-level message, which Slack supports only
    ///     in channels where the whole channel is one agent session, such as Slack Code; elsewhere
    ///     `chat.startStream` fails with `invalid_thread_ts`.
    ///   - recipient: The user the reply is for. Slack requires it when streaming into a channel rather than a
    ///     DM with the app.
    ///   - taskDisplay: How ``StreamingMessage/Part/task(_:)`` parts render.
    ///   - blocks: Blocks rendered at the bottom of the finished message, up to 50.
    ///   - sessionStatus: The agent session's status after the stream stops, such as `suspended`. Slack
    ///     defaults to `active`.
    ///   - minimumInterval: The shortest time between two calls. `chat.appendStream` is a Tier 4 method.
    ///   - isolation: The caller's actor isolation, inherited by default so the sequence is read in its context.
    /// - Returns: The message's `ts`.
    @discardableResult
    public func streamMessage<Parts: AsyncSequence>(
        _ parts: Parts,
        channel: String,
        threadTs: String? = nil,
        recipient: StreamingMessage.Recipient? = nil,
        taskDisplay: StreamingMessage.TaskDisplay = .timeline,
        blocks: [Block]? = nil,
        sessionStatus: String? = nil,
        minimumInterval: Duration = .seconds(1),
        isolation: isolated (any Actor)? = #isolation,
    ) async throws -> String where Parts.Element == StreamingMessage.Part {
        let transport = WebAPIStreamingTransport(
            client: self,
            channel: channel,
            threadTs: threadTs,
            recipient: recipient,
            taskDisplay: taskDisplay,
            sessionStatus: sessionStatus,
        )
        return try await StreamingMessageSender(transport: transport, blocks: blocks, minimumInterval: minimumInterval)
            .send(parts, isolation: isolation)
    }
}
#endif
