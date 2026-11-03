#if WebAPI_Chat
extension StreamingMessage {
    /// One streaming message, with its channel and options bound, that the app can stop from outside its parts.
    ///
    /// Create it with ``APIProtocol/makeStreamingMessage(channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:)``,
    /// which makes no request, and register it where the code that learns Slack has ended the session can reach
    /// it, such as an `agent_session_stopped` handler, before you await anything. Then stream the parts with
    /// `send(_:)`, which returns once the message has been delivered:
    ///
    /// ```swift
    /// let delivery = client.makeStreamingMessage(channel: channel, threadTs: threadTs)
    /// // Register delivery with your agent_session_stopped handler before awaiting.
    /// // The handler calls `await delivery.notifySessionStopped()`.
    /// let ts = try await delivery.send(parts)
    /// ```
    ///
    /// ``notifySessionStopped()`` ends the message's delivery whatever the parts sequence is doing, including after
    /// it has finished while the closing calls or their `Retry-After` waits remain. ``messageTs`` shows the
    /// message's `ts` as soon as `chat.startStream` succeeds.
    ///
    /// A delivery sends a single message. The first `send` reserves it before it reads the parts or calls Slack,
    /// and holds it until it returns or throws; see ``State``. Any other `send`, whether at the same time or
    /// later, throws ``AlreadyUsed`` without reading its parts or calling Slack, and leaves the message to the
    /// call that holds it. Create a new delivery for every message.
    public actor Delivery {
        /// Where a delivery is in its single message's lifecycle.
        public enum State: Sendable, Hashable {
            /// `send` has not been called yet.
            case ready
            /// A `send` call holds the delivery and has not returned or thrown.
            case streaming
            /// Delivery has completed. The delivery cannot be used again.
            case ended
        }

        /// Thrown by `send` when another `send` holds the delivery or has already used it.
        public struct AlreadyUsed: Swift.Error, Sendable, Hashable {
            public init() {}
        }

        /// The delivery's lifecycle state.
        public private(set) var state: State = .ready
        /// The message's `ts`, from the first `chat.startStream` that succeeded, or `nil` before it.
        ///
        /// It stays available when a later call fails or Slack ends the session, so the app can still refer to a
        /// message that `send` did not return.
        public private(set) var messageTs: String?
        /// Whether Slack ended the session before the message ended, through ``notifySessionStopped()`` or the
        /// parts sequence throwing ``SessionStopped``.
        public private(set) var isSessionStopped = false

        /// The engine with the channel and options bound. It is immutable and `Sendable`, so `send` reads it in
        /// the caller's isolation.
        private nonisolated let sender: StreamingMessageSender
        /// The holding call's stop signal and buffer, kept only while it streams.
        private var stopSignal: SessionStopSignal?
        private var buffer: PartBuffer?

        init(sender: StreamingMessageSender) {
            self.sender = sender
        }

        /// Streams a Sendable input with concurrent reading and delivery, and returns the message's `ts`.
        ///
        /// A delivery failure, or ``notifySessionStopped()``, cancels input iteration immediately, including while
        /// it waits for another element. The input must cooperate with cancellation; `AsyncStream` and
        /// `AsyncThrowingStream` do so. The method returns only once the input's iteration ends, so an input that
        /// ignores cancellation delays the return after a failure, a session stop, or a cancellation of the
        /// calling task.
        ///
        /// Swift picks this overload when the argument's static type is `Sendable`, and the input is then read in
        /// a child task rather than in the caller's isolation. Completion behavior is otherwise the same as
        /// ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)``.
        ///
        /// - Throws: ``AlreadyUsed`` when the delivery has been sent before or is being sent.
        @discardableResult
        public func send<Parts: AsyncSequence & Sendable>(
            _ parts: Parts,
            isolation: isolated (any Actor)? = #isolation,
        ) async throws -> String where Parts.Element == StreamingMessage.Part {
            try await sender.run(parts, delivery: self, isolation: isolation)
        }

        /// Streams any input, read in the caller's isolation, and returns the message's `ts`.
        ///
        /// The input need not be `Sendable`: this method runs in the caller's isolation, and only the delivery's
        /// state is read and changed on the delivery actor. Because reading and delivery then share the calling
        /// task, a failed call is noticed only when `parts` yields its next element or ends. Cancelling the
        /// calling task, or ``notifySessionStopped()``, stops delivery promptly, but the method still returns only
        /// once `parts` yields or ends. Completion behavior is otherwise the same as
        /// ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)``.
        ///
        /// - Throws: ``AlreadyUsed`` when the delivery has been sent before or is being sent.
        @discardableResult
        public func send<Parts: AsyncSequence>(
            _ parts: Parts,
            isolation: isolated (any Actor)? = #isolation,
        ) async throws -> String where Parts.Element == StreamingMessage.Part {
            try await sender.run(parts, delivery: self, isolation: isolation)
        }

        /// Records that Slack has already ended the message's session, as the stop button does.
        ///
        /// This has the effect of the parts sequence throwing ``SessionStopped``, without waiting for the
        /// sequence: the parts and blocks not yet sent are discarded, and waits between calls end. Once delivery
        /// observes the signal, it starts no further call or retry, not even the best-effort stop after a failure
        /// or a cancellation. A request that has already passed the stop check may still begin; `send` waits for
        /// it without cancelling it, ignores its outcome, and throws ``SessionStopped``.
        ///
        /// Before `send` is called, the stop is kept, and `send` throws ``SessionStopped`` without reading its
        /// parts or calling Slack. Once the message has ended, this has no effect.
        ///
        /// Delivery stops at once, but `send` returns only once it is done reading the parts. A `Sendable`
        /// sequence is read in a child task, which is cancelled, so a sequence that honors cancellation, such as
        /// an `AsyncStream`, ends even while it waits for an element. A sequence read in the caller's isolation is
        /// not interrupted: `send` returns when it yields its next element or ends. Either way, stop whatever
        /// produces the parts separately.
        public func notifySessionStopped() async {
            guard state != .ended else { return }
            isSessionStopped = true
            guard let stopSignal, let buffer else { return }
            // Raising before waking delivery makes delivery see the signal once it takes the empty final batch.
            await stopSignal.raise()
            await buffer.discard()
        }

        /// Reserves the delivery for one `send`, or throws ``AlreadyUsed``. Returns `false` when Slack ended the
        /// session before, so the message must not start.
        ///
        /// It does not suspend, so of two calls that send at the same time, exactly one takes it.
        func begin(stopSignal: SessionStopSignal, buffer: PartBuffer) throws -> Bool {
            guard state == .ready else { throw AlreadyUsed() }
            state = .streaming
            self.stopSignal = stopSignal
            self.buffer = buffer
            return !isSessionStopped
        }

        /// Records the `ts` of the message that a successful `chat.startStream` posted.
        func started(ts: String) {
            messageTs = ts
        }

        /// Ends the message and returns whether Slack stopped it before this transition.
        func end() -> Bool {
            state = .ended
            stopSignal = nil
            buffer = nil
            return isSessionStopped
        }
    }
}
#endif
