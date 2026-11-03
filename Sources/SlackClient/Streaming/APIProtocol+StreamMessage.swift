#if WebAPI_Chat
import SlackBlockKit

extension APIProtocol {
    /// Streams a Sendable input with concurrent reading and delivery. A delivery failure cancels input
    /// iteration immediately, including while it waits for another element. The input must cooperate with
    /// cancellation; `AsyncStream` and `AsyncThrowingStream` do so.
    ///
    /// Swift picks this overload when the argument's static type is `Sendable`. That includes an `AsyncStream`
    /// mapped directly with `map`, because `AsyncMapSequence` is `Sendable` when its base and elements are; the
    /// input, including the mapping closure, is then read in a child task rather than in the caller's
    /// isolation. Generic code whose sequence type is constrained only to `AsyncSequence` picks the
    /// caller-isolated overload, even when the concrete type is `Sendable`.
    ///
    /// Other arguments and completion behavior are the same as the caller-isolated sequence overload.
    @discardableResult
    public func streamMessage<Parts: AsyncSequence & Sendable>(
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
            client: self, channel: channel, threadTs: threadTs, recipient: recipient,
            taskDisplay: taskDisplay, sessionStatus: sessionStatus,
        )
        return try await StreamingMessageSender(transport: transport, blocks: blocks, minimumInterval: minimumInterval)
            .send(parts, isolation: isolation)
    }

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
    /// - When the calling task is cancelled, the parts so far and `blocks` go out. A request in progress is not
    ///   abandoned: the method waits for Slack's answer, so a message that a start in progress posts is stopped
    ///   too. The closing calls run in a task that does not inherit the cancellation. A call that Slack rejected
    ///   as rate limited is not retried in the cancelled task: its parts go out with the closing calls, after
    ///   its `Retry-After` delay.
    /// - When a call fails, including one of the closing calls, the message is stopped without further content
    ///   once it has a `ts`, and the error is rethrown, even if that stop fails too. Slack answering
    ///   `"ok": false` throws ``StreamingMessage/Error``. Rate-limited calls (HTTP 429) are retried after their
    ///   `Retry-After` delay, up to three attempts. Other failed calls are not resent, because a call that fails
    ///   in flight may already have reached Slack.
    ///
    /// This overload reads `parts` in the calling task's isolation, so it need not be `Sendable`. Swift picks
    /// it for any sequence whose static type is not `Sendable`, including a sequence in generic code constrained
    /// only to `AsyncSequence`; a `Sendable` sequence, such as a directly mapped `AsyncStream`, picks the
    /// overload that reads it in a child task. Because reading and delivery then share the calling task, a
    /// failed call is noticed only when `parts` yields its next element or ends: while `parts` is idle, the
    /// method does not return, and it does not cancel `parts`.
    ///
    /// To stop a reply early while still finishing it, end `parts`, for example by cancelling the task that
    /// yields to an `AsyncStream`; that task can still yield closing parts, such as a note that the reply was
    /// stopped. Ending `parts`, with any error, does not stop whatever produces them; stop the producer
    /// separately.
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
