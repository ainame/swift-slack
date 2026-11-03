#if WebAPI_Chat
extension StreamingMessage {
    /// Controls one streaming message from outside its parts sequence.
    ///
    /// Pass a handle to one `streamMessage` call, and keep it where the code that learns Slack has ended the
    /// session can reach it, such as an `agent_session_stopped` handler. ``markSessionStopped()`` then ends the
    /// message's delivery whatever the parts sequence is doing, including after it has finished while the
    /// closing calls or their `Retry-After` waits remain. ``messageTs`` shows the message's `ts` as soon as
    /// `chat.startStream` succeeds.
    ///
    /// ```swift
    /// let message = StreamingMessage.Handle()
    /// // Register message with your agent_session_stopped handler before awaiting.
    /// // The handler calls `await message.markSessionStopped()`.
    /// try await client.streamMessage(parts, channel: channel, threadTs: threadTs, handle: message)
    /// ```
    ///
    /// A handle serves a single message. The first `streamMessage` call that receives it reserves it before
    /// it reads the parts or calls Slack, and keeps it until it returns or throws; see ``State``. Any other call
    /// that receives it, whether at the same time or later, throws ``AlreadyUsed`` without reading its parts or
    /// calling Slack, and leaves the handle to the call that holds it. Create a new handle for every message.
    public actor Handle {
        /// Where a handle is in its single message's lifecycle.
        public enum State: Sendable, Hashable {
            /// No `streamMessage` call has received the handle yet.
            case ready
            /// A `streamMessage` call holds the handle and has not returned or thrown.
            case streaming
            /// Delivery has completed. The handle cannot be used again.
            case ended
        }

        /// Thrown by `streamMessage` when it receives a handle that another call holds or has already used.
        public struct AlreadyUsed: Swift.Error, Sendable, Hashable {
            public init() {}
        }

        /// The handle's lifecycle state.
        public private(set) var state: State = .ready
        /// The message's `ts`, from the first `chat.startStream` that succeeded, or `nil` before it.
        ///
        /// It stays available when a later call fails or Slack ends the session, so the app can still refer to a
        /// message that `streamMessage` did not return.
        public private(set) var messageTs: String?
        /// Whether Slack ended the session before the message ended, through ``markSessionStopped()`` or the
        /// parts sequence throwing ``SessionStopped``.
        public private(set) var isSessionStopped = false

        /// The holding call's stop signal and buffer, kept only while it streams.
        private var stopSignal: SessionStopSignal?
        private var buffer: PartBuffer?

        public init() {}

        /// Records that Slack has already ended the message's session, as the stop button does.
        ///
        /// This has the effect of the parts sequence throwing ``SessionStopped``, without waiting for the
        /// sequence: the parts and blocks not yet sent are discarded, and waits between calls end. Once delivery
        /// observes the signal, it starts no further call or retry. A request that has already passed the stop
        /// check may still begin; `streamMessage` waits for it without cancelling it, ignores its outcome, and
        /// throws ``SessionStopped``.
        ///
        /// Before `streamMessage` receives the handle, the stop is kept, and that call throws
        /// ``SessionStopped`` without reading its parts or calling Slack. Once the message has ended, this has no
        /// effect.
        ///
        /// Delivery stops at once, but `streamMessage` returns only once it is done reading the parts. A
        /// `Sendable` sequence is read in a child task, which is cancelled, so a sequence that honors
        /// cancellation, such as an `AsyncStream`, ends even while it waits for an element. A sequence read in
        /// the caller's isolation is not interrupted: `streamMessage` returns when it yields its next element or
        /// ends. Either way, stop whatever produces the parts separately.
        public func markSessionStopped() async {
            guard state != .ended else { return }
            isSessionStopped = true
            guard let stopSignal, let buffer else { return }
            // Raising before waking delivery makes delivery see the signal once it takes the empty final batch.
            await stopSignal.raise()
            await buffer.discard()
        }

        /// Reserves the handle for one message, or throws ``AlreadyUsed``. Returns `false` when Slack ended the
        /// session before, so the message must not start.
        ///
        /// It does not suspend, so of two calls that receive the handle at the same time, exactly one takes it.
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
