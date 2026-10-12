#if WebAPI_Chat
import SlackBlockKit

/// The three Web API calls behind a streaming message. ``StreamingMessageSender`` decides when to make them.
///
/// Each call takes the message's ``SessionStopSignal``. A transport that retries checks it before every retry
/// and waits through it, so that no retry starts once Slack has ended the session.
protocol StreamingMessageTransport: Sendable {
    /// Calls `chat.startStream` and returns the message's `ts`.
    func start(chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws -> String
    /// Calls `chat.appendStream`.
    func append(ts: String, chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws
    /// Calls `chat.stopStream`.
    func stop(
        ts: String,
        chunks: [StreamingMessage.Part],
        blocks: [Block]?,
        stopSignal: SessionStopSignal,
    ) async throws
}

/// Thrown by a transport when Slack rejected a call as rate limited (HTTP 429) and the task was cancelled before
/// the retry.
///
/// Slack did not process the rejected call, so its parts are still unsent: the sender sends them with the closing
/// calls, which do not run in the cancelled task, once `retryAt` has passed. Other failures do not mean this,
/// because a call that failed in flight may already have reached Slack.
struct RateLimitedCallCancelled: Error {
    /// When Slack accepts calls again, from the rejection's `Retry-After`.
    var retryAt: ContinuousClock.Instant
}

/// Sends a sequence of parts as one streaming message.
///
/// The caller's task reads the sequence into a ``PartBuffer``, and a child task sends whatever the buffer holds
/// with each call. Reading in the caller's task keeps the sequence in the caller's isolation, so it need not be
/// `Sendable`.
///
/// When the sequence throws ``StreamingMessage/SessionStopped``, the caller's task raises a ``SessionStopSignal``,
/// which every path checks before it starts a call, and after a call before it acts on the outcome.
struct StreamingMessageSender<Transport: StreamingMessageTransport>: Sendable {
    let transport: Transport
    let blocks: [Block]?
    let minimumInterval: Duration
    /// Waits between calls and before retries. Tests replace it to observe the waits.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func send<Parts: AsyncSequence>(
        _ parts: Parts,
        isolation: isolated (any Actor)? = #isolation,
    ) async throws -> String where Parts.Element == StreamingMessage.Part {
        let buffer = PartBuffer()
        let stopSignal = SessionStopSignal(sleep: sleep)
        return try await withThrowingTaskGroup(of: String.self, returning: String.self, isolation: isolation) { group in
            group.addTask {
                try await deliver(from: buffer, stopSignal: stopSignal)
            }
            do {
                for try await part in parts {
                    // The buffer closes when delivery ends early, after a failed call or a cancellation.
                    guard await buffer.append(part) else { break }
                }
                await buffer.finish(throwing: nil)
            } catch let stopped as StreamingMessage.SessionStopped {
                // The signal is raised before the input finishes, so delivery sees it with the final batch. It
                // takes effect even when delivery has already closed the buffer after a failed call.
                await stopSignal.raise()
                await buffer.finish(throwing: stopped)
                // A call in flight cannot be withdrawn: wait for it without cancelling it, and ignore its outcome.
                _ = try? await group.next()
                throw stopped
            } catch {
                await buffer.finish(throwing: error)
            }
            guard let ts = try await group.next() else {
                preconditionFailure("delivery returns a ts or throws")
            }
            return ts
        }
    }

    private func deliver(from buffer: PartBuffer, stopSignal: SessionStopSignal) async throws -> String {
        var ts: String?
        let ending: PartBuffer.Batch
        var retryAt: ContinuousClock.Instant?
        do {
            ending = try await stream(from: buffer, ts: &ts, retryAt: &retryAt, stopSignal: stopSignal)
        } catch {
            await buffer.close()
            // Once Slack has ended the session, the failure no longer matters and the message needs no stop.
            try await stopSignal.check()
            // Stop the message so it does not stay streaming; the failed call may have carried the last parts.
            if let ts {
                try? await Self.uncancellable { [transport] in
                    try await stopSignal.check()
                    try await transport.stop(ts: ts, chunks: [], blocks: nil, stopSignal: stopSignal)
                }
                try await stopSignal.check()
            }
            throw error
        }
        // Once Slack has ended the session, the final batch and the closing blocks are discarded.
        try await stopSignal.check()
        if let failure = ending.failure, ts == nil, ending.parts.isEmpty {
            // The input failed before it produced anything, so there is no message to post.
            throw failure
        }

        // The closing calls run even when the caller was cancelled, because cancelling must still stop the
        // message, and HTTP transports abandon requests made from a cancelled task.
        let messageTs: String
        do {
            messageTs = try await Self.uncancellable { [transport, blocks, ts, retryAt] in
                if let retryAt {
                    // Slack rejected the last call as rate limited, so wait out its Retry-After first.
                    try await stopSignal.sleep(for: ContinuousClock.now.duration(to: retryAt))
                }
                var chunks = ending.parts
                let messageTs: String
                if let ts {
                    messageTs = ts
                } else {
                    try await stopSignal.check()
                    // A stream needs content to start; start with a space when nothing else came.
                    messageTs = try await transport.start(
                        chunks: chunks.isEmpty ? [.markdown(" ")] : chunks,
                        stopSignal: stopSignal,
                    )
                    chunks = []
                }
                try await stopSignal.check()
                try await transport.stop(ts: messageTs, chunks: chunks, blocks: blocks, stopSignal: stopSignal)
                return messageTs
            }
        } catch {
            try await stopSignal.check()
            throw error
        }
        if let failure = ending.failure {
            throw failure
        }
        return messageTs
    }

    /// Starts and appends to the message until the input ends, and returns the final batch for the closing calls.
    ///
    /// `retryAt` is set when Slack rate limited the last call and the closing calls must wait before they start.
    private func stream(
        from buffer: PartBuffer,
        ts: inout String?,
        retryAt: inout ContinuousClock.Instant?,
        stopSignal: SessionStopSignal,
    ) async throws -> PartBuffer.Batch {
        while true {
            var batch = await buffer.next()
            if !batch.isFinal, Task.isCancelled {
                // Cancelling ends the input: the batch just taken and everything still buffered go out with the
                // closing calls.
                batch = await buffer.close(prepending: batch.parts)
            }
            if batch.isFinal {
                return batch
            }

            try await stopSignal.check()
            do {
                if let ts {
                    try await transport.append(ts: ts, chunks: batch.parts, stopSignal: stopSignal)
                } else {
                    ts = try await transport.start(chunks: batch.parts, stopSignal: stopSignal)
                }
            } catch let cancelled as RateLimitedCallCancelled {
                // Slack did not process the batch, so it goes out with the closing calls like the rest.
                try await stopSignal.check()
                retryAt = cancelled.retryAt
                return await buffer.close(prepending: batch.parts)
            }
            // A cancelled wait returns early, and the next batch is the final one. The wait throws once Slack has
            // ended the session, including during the call that just finished.
            try await stopSignal.sleep(for: minimumInterval)
        }
    }

    /// Runs `operation` in a new task, which does not inherit the caller's cancellation.
    ///
    /// This is the only unstructured task in streaming: the caller still awaits its result, so it does not
    /// outlive `send`.
    private static func uncancellable<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        try await Task { try await operation() }.value
    }
}

/// Records that Slack has ended a streaming message's session: the one terminal state every request path checks.
///
/// The sender raises it when the input throws ``StreamingMessage/SessionStopped``. Raising it cannot withdraw a
/// call already in progress; it makes ``check()`` throw before the next one, and it ends ``sleep(for:)`` waits.
actor SessionStopSignal {
    private let timer: @Sendable (Duration) async throws -> Void
    private var isRaised = false
    /// The waits in ``sleep(for:)`` and ``waitUntilRaised()``, by an ID so that a timer that fires late cannot
    /// resume a later wait.
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextWaiterID = 0

    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        timer = sleep
    }

    func raise() {
        isRaised = true
        for waiter in waiters.values {
            waiter.resume()
        }
        waiters = [:]
    }

    /// Throws ``StreamingMessage/SessionStopped`` once the signal is raised.
    func check() throws {
        if isRaised {
            throw StreamingMessage.SessionStopped()
        }
    }

    /// Waits for `duration`, returning early when the task is cancelled, and throws
    /// ``StreamingMessage/SessionStopped`` when the signal is raised before or during the wait.
    func sleep(for duration: Duration) async throws {
        try check()
        guard duration > .zero else { return }
        let id = takeWaiterID()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [timer] in
                // The timer inherits the caller's cancellation, so a cancelled caller also ends the wait.
                try? await timer(duration)
                await self.resumeWaiter(id)
            }
            // Storing the waiter does not leave the actor, so neither the timer nor a raise can miss it.
            await withCheckedContinuation { waiters[id] = $0 }
            group.cancelAll()
        }
        try check()
    }

    /// Waits until the signal is raised.
    func waitUntilRaised() async {
        guard !isRaised else { return }
        let id = takeWaiterID()
        await withCheckedContinuation { waiters[id] = $0 }
    }

    private func takeWaiterID() -> Int {
        defer { nextWaiterID += 1 }
        return nextWaiterID
    }

    private func resumeWaiter(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume()
    }
}

/// Collects parts while a call is in flight so the next call sends them together.
///
/// A producer can yield a part per token, but the streaming methods are rate limited, so the sender takes
/// everything buffered between calls. Adjacent markdown and adjacent blocks merge up to Slack's limits.
actor PartBuffer {
    struct Batch: Sendable {
        var parts: [StreamingMessage.Part]
        /// `true` once the input has ended: no parts follow this batch.
        var isFinal: Bool
        /// The error the input ended with.
        var failure: (any Error)?
    }

    /// Slack limits `markdown_text` to 12,000 characters.
    static let markdownLimit = 12000
    /// Slack limits a `blocks` chunk to 50 blocks.
    static let blocksLimit = 50

    private var parts: [StreamingMessage.Part] = []
    private var isFinished = false
    private var failure: (any Error)?
    private var isClosed = false
    /// The sender waiting in ``next()``. There is only one sender, so one waiter is enough.
    private var waiter: CheckedContinuation<Void, Never>?

    /// Adds `part`, or returns `false` once the sender has closed the buffer and takes no more parts.
    @discardableResult
    func append(_ part: StreamingMessage.Part) -> Bool {
        guard !isClosed else { return false }
        add(part)
        resumeWaiter()
        return true
    }

    /// Ends the input, with the error it threw if any.
    func finish(throwing error: (any Error)?) {
        guard !isFinished else { return }
        isFinished = true
        failure = error
        resumeWaiter()
    }

    /// Stops taking parts and returns everything buffered as the final batch, after `taken`: parts the sender
    /// took earlier but did not send.
    @discardableResult
    func close(prepending taken: [StreamingMessage.Part] = []) -> Batch {
        isClosed = true
        let buffered = parts
        parts = []
        for part in taken + buffered {
            add(part)
        }
        return take(isFinal: true)
    }

    /// Waits until parts are available, the input has ended, or the sender is cancelled, then takes everything
    /// buffered.
    func next() async -> Batch {
        while parts.isEmpty, !isFinished, !Task.isCancelled {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    precondition(waiter == nil, "PartBuffer supports one sender")
                    waiter = continuation
                }
            } onCancel: {
                // The handler cannot reach the actor's state synchronously. If it runs before the sender
                // suspends, this task waits for the actor and resumes the waiter once it is stored.
                Task { await self.resumeWaiter() }
            }
        }
        return take(isFinal: isFinished)
    }

    private func take(isFinal: Bool) -> Batch {
        defer { parts = [] }
        return Batch(parts: parts, isFinal: isFinal, failure: isFinal ? failure : nil)
    }

    private func add(_ part: StreamingMessage.Part) {
        switch part {
        case let .markdown(text):
            appendMarkdown(text)
        case let .blocks(blocks):
            appendBlocks(blocks)
        case .task, .plan:
            parts.append(part)
        }
    }

    private func appendMarkdown(_ text: String) {
        var text = Substring(text)
        if case let .markdown(previous)? = parts.last, previous.count < Self.markdownLimit {
            let head = text.prefix(Self.markdownLimit - previous.count)
            parts[parts.count - 1] = .markdown(previous + head)
            text = text.dropFirst(head.count)
        }
        while !text.isEmpty {
            parts.append(.markdown(String(text.prefix(Self.markdownLimit))))
            text = text.dropFirst(Self.markdownLimit)
        }
    }

    private func appendBlocks(_ blocks: [Block]) {
        var blocks = blocks[...]
        if case let .blocks(previous)? = parts.last, previous.count < Self.blocksLimit {
            let head = blocks.prefix(Self.blocksLimit - previous.count)
            parts[parts.count - 1] = .blocks(previous + head)
            blocks = blocks.dropFirst(head.count)
        }
        while !blocks.isEmpty {
            parts.append(.blocks(Array(blocks.prefix(Self.blocksLimit))))
            blocks = blocks.dropFirst(Self.blocksLimit)
        }
    }

    private func resumeWaiter() {
        waiter?.resume()
        waiter = nil
    }
}
#endif
