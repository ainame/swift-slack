#if WebAPI_Chat
import Logging
import OpenAPIRuntime
import SlackBlockKit

/// The three Web API calls behind a streaming message. ``StreamingMessageSender`` decides when to make them.
///
/// Each call takes the message's ``SessionStopSignal``. A transport that retries checks it before every retry
/// and waits through it, so that no retry starts once Slack has ended the session.
///
/// Calls run in the caller's task and honor its cancellation. A request abandoned on cancellation may still have
/// reached Slack, so the sender never resends it. A wait before a rate-limit retry that ends on cancellation
/// throws `CancellationError` instead of retrying.
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
    /// Calls `chat.stopStream` once without chunks or blocks, to end a message whose delivery failed or was
    /// cancelled. A rate-limited call is not retried.
    func stopOnce(ts: String, stopSignal: SessionStopSignal) async throws
}

/// Sends a sequence of parts as one streaming message.
///
/// The caller's task reads the sequence into a ``PartBuffer``, and a child task sends whatever the buffer holds
/// with each call. Reading in the caller's task keeps the sequence in the caller's isolation, so it need not be
/// `Sendable`.
///
/// Every message is a ``StreamingMessage/Delivery``, whose `send` calls `run` and which `run` reserves at its first
/// suspension. When the sequence throws ``StreamingMessage/SessionStopped``, or the app marks the delivery, the
/// delivery raises the message's ``SessionStopSignal``, which every path checks before it starts a call, and after
/// a call before it acts on the outcome, and it wakes delivery waiting for parts.
///
/// The sender holds only immutable, `Sendable` values, so a delivery's `send` can use it in the caller's
/// isolation. The transport is an existential so that a delivery does not depend on its type.
///
/// Cancelling the task ends delivery like a failed call: the parts and blocks not yet sent are discarded, and the
/// message is stopped without content once it has a `ts`.
struct StreamingMessageSender: Sendable {
    let transport: any StreamingMessageTransport
    let blocks: [Block]?
    let minimumInterval: Duration
    /// Reports a failed cleanup stop, which delivery otherwise does not surface.
    let logger: Logger
    /// Waits between calls and before retries. Tests replace it to observe the waits.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Tests disable the shield to exercise the fallback on a newer OS.
    var useCancellationShield = true

    /// Sendable inputs can be read by a child task. Delivery failures then cancel the reader even while its
    /// next element is suspended, rather than waiting for the producer to yield again.
    func run<Parts: AsyncSequence & Sendable>(
        _ parts: Parts,
        delivery: StreamingMessage.Delivery,
        isolation: isolated (any Actor)? = #isolation,
    ) async throws -> String where Parts.Element == StreamingMessage.Part {
        let buffer = PartBuffer()
        let stopSignal = SessionStopSignal(sleep: sleep)
        guard try await delivery.begin(stopSignal: stopSignal, buffer: buffer) else {
            _ = await delivery.end()
            throw StreamingMessage.SessionStopped()
        }
        do {
            let ts = try await withThrowingTaskGroup(
                of: String?.self,
                returning: String.self,
                isolation: isolation,
            ) { group in
                group.addTask {
                    try await deliver(from: buffer, stopSignal: stopSignal, delivery: delivery)
                }
                group.addTask {
                    do {
                        for try await part in parts {
                            guard await buffer.append(part) else { break }
                        }
                        await buffer.finish(throwing: nil)
                    } catch let stopped as StreamingMessage.SessionStopped {
                        await delivery.notifySessionStopped()
                        await buffer.finish(throwing: stopped)
                    } catch {
                        await buffer.finish(throwing: error)
                    }
                    return nil
                }
                // Delivery ending, including when Slack ends the session, cancels the reader.
                defer { group.cancelAll() }
                while let result = try await group.next() {
                    if let ts = result {
                        return ts
                    }
                }
                preconditionFailure("delivery returns a ts or throws")
            }
            if await delivery.end() {
                throw StreamingMessage.SessionStopped()
            }
            return ts
        } catch {
            if await delivery.end() {
                throw StreamingMessage.SessionStopped()
            }
            throw error
        }
    }

    func run<Parts: AsyncSequence>(
        _ parts: Parts,
        delivery: StreamingMessage.Delivery,
        isolation: isolated (any Actor)? = #isolation,
    ) async throws -> String where Parts.Element == StreamingMessage.Part {
        let buffer = PartBuffer()
        let stopSignal = SessionStopSignal(sleep: sleep)
        guard try await delivery.begin(stopSignal: stopSignal, buffer: buffer) else {
            _ = await delivery.end()
            throw StreamingMessage.SessionStopped()
        }
        do {
            let ts = try await withThrowingTaskGroup(
                of: String.self,
                returning: String.self,
                isolation: isolation,
            ) { group in
                group.addTask {
                    try await deliver(from: buffer, stopSignal: stopSignal, delivery: delivery)
                }
                do {
                    for try await part in parts {
                        // The buffer closes when delivery ends early, after a failed call, a cancellation, or a
                        // session stop through the delivery. An idle input is not interrupted.
                        guard await buffer.append(part) else { break }
                    }
                    await buffer.finish(throwing: nil)
                } catch let stopped as StreamingMessage.SessionStopped {
                    // The signal is raised before the input finishes, so delivery sees it with the final batch.
                    // It takes effect even when delivery has already closed the buffer after a failed call.
                    await delivery.notifySessionStopped()
                    await buffer.finish(throwing: stopped)
                    // A call in flight cannot be withdrawn: wait for it without cancelling it, and ignore its
                    // outcome.
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
            if await delivery.end() {
                throw StreamingMessage.SessionStopped()
            }
            return ts
        } catch {
            if await delivery.end() {
                throw StreamingMessage.SessionStopped()
            }
            throw error
        }
    }

    private func deliver(
        from buffer: PartBuffer,
        stopSignal: SessionStopSignal,
        delivery: StreamingMessage.Delivery,
    ) async throws -> String {
        var ts: String?
        let ending: PartBuffer.Batch
        let messageTs: String
        do {
            ending = try await stream(from: buffer, ts: &ts, stopSignal: stopSignal, delivery: delivery)
            // Once Slack has ended the session, the final batch and the closing blocks are discarded.
            try await stopSignal.check()
            if let failure = ending.failure, ts == nil, ending.parts.isEmpty {
                // The input failed before it produced anything, so there is no message to post.
                throw failure
            }
            messageTs = try await close(ts: &ts, ending: ending, stopSignal: stopSignal, delivery: delivery)
        } catch {
            await buffer.close()
            try await abandon(ts: ts, stopSignal: stopSignal)
            throw error
        }
        if let failure = ending.failure {
            throw failure
        }
        return messageTs
    }

    /// Starts and appends to the message until the input ends, and returns the final batch for the closing calls.
    ///
    /// Throws once the task is cancelled, which discards the batch just taken and everything still buffered.
    private func stream(
        from buffer: PartBuffer,
        ts: inout String?,
        stopSignal: SessionStopSignal,
        delivery: StreamingMessage.Delivery,
    ) async throws -> PartBuffer.Batch {
        while true {
            // A cancelled task stops waiting here, whether the input is idle or has ended because of the
            // cancellation. A session stop through the delivery also wakes this wait, with an empty final batch.
            let batch = await buffer.next()
            try Self.checkCancellation(rethrowing: batch.failure)
            if batch.isFinal {
                return batch
            }

            try await stopSignal.check()
            // `ts` is stored and shown on the delivery as soon as a start returns, so a cancellation or session
            // stop noticed later still knows the message.
            if let ts {
                try await transport.append(ts: ts, chunks: batch.parts, stopSignal: stopSignal)
            } else {
                let started = try await transport.start(chunks: batch.parts, stopSignal: stopSignal)
                ts = started
                await delivery.started(ts: started)
            }
            // A cancelled wait returns early, and the next batch throws. The wait throws once Slack has ended the
            // session, including during the call that just finished.
            try await stopSignal.sleep(for: minimumInterval)
        }
    }

    /// Sends the final batch and the closing blocks, starting the message first when it has no `ts` yet.
    ///
    /// The final batch fits one request, because the buffer takes bounded batches until the input has ended. When
    /// the task is cancelled after a start made here, the message keeps that start's `ts` for the cleanup stop.
    private func close(
        ts: inout String?,
        ending: PartBuffer.Batch,
        stopSignal: SessionStopSignal,
        delivery: StreamingMessage.Delivery,
    ) async throws -> String {
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
            ts = messageTs
            await delivery.started(ts: messageTs)
            chunks = []
            try Self.checkCancellation(rethrowing: ending.failure)
        }
        try await stopSignal.check()
        try await transport.stop(ts: messageTs, chunks: chunks, blocks: blocks, stopSignal: stopSignal)
        try await stopSignal.check()
        return messageTs
    }

    /// Ends delivery after a failed call or a cancellation, and leaves rethrowing the error to the caller.
    ///
    /// Once the message has a `ts`, it is stopped with one call that carries no parts or blocks: a call that failed
    /// or was abandoned may already have delivered its parts. The call is protected from cancellation, because
    /// HTTP transports abandon requests made from a cancelled task. On older Apple OS versions, an awaited task
    /// provides that protection because cancellation shields are unavailable. Its failure is logged as a warning
    /// rather than thrown, so the caller still rethrows the original error. Once Slack has ended the session, no
    /// call is made and ``StreamingMessage/SessionStopped`` is thrown instead. A failure is not logged if the
    /// session-stop signal is observed before logging.
    private func abandon(ts: String?, stopSignal: SessionStopSignal) async throws {
        try await stopSignal.check()
        guard let ts else { return }
        let failure: (any Error)? = if #available(macOS 27, iOS 27, macCatalyst 27, tvOS 27, watchOS 27, visionOS 27, *),
                                       useCancellationShield {
            await withTaskCancellationShield {
                await Self.cleanupStop(ts: ts, transport: transport, stopSignal: stopSignal)
            }
        } else {
            // A new task does not inherit cancellation; awaiting it keeps cleanup within this operation's lifetime.
            await Task { [transport] in
                await Self.cleanupStop(ts: ts, transport: transport, stopSignal: stopSignal)
            }.value
        }
        // A failure is expected once Slack has ended the session, so the session stop takes precedence over it.
        try await stopSignal.check()
        if let failure {
            logCleanupFailure(failure, ts: ts)
        }
    }

    /// Makes the cleanup stop and returns its error rather than throwing it, so that both ways of protecting it
    /// from cancellation handle the outcome alike.
    private static func cleanupStop(
        ts: String,
        transport: any StreamingMessageTransport,
        stopSignal: SessionStopSignal,
    ) async -> (any Error)? {
        do {
            try await stopSignal.check()
            try await transport.stopOnce(ts: ts, stopSignal: stopSignal)
            return nil
        } catch {
            return error
        }
    }

    /// Logs only identifiers and error codes. Error descriptions are left out: a `ClientError` describes the
    /// request, including its headers and body, and the response.
    private func logCleanupFailure(_ error: any Error, ts: String) {
        var metadata: Logger.Metadata = [
            "slack.method": "chat.stopStream",
            "slack.message_ts": "\(ts)",
            "error.type": "\(String(reflecting: type(of: error)))",
        ]
        if let error = error as? StreamingMessage.Error {
            metadata["slack.error"] = "\(error.code)"
        } else if let error = error as? ClientError, let status = error.response?.status.code {
            metadata["http.status_code"] = "\(status)"
        }
        logger.warning(
            "Cleanup chat.stopStream failed after delivery failed or was cancelled; the message may remain streaming",
            metadata: metadata,
        )
    }

    /// Throws once the task is cancelled. When the input ended with an error, that error is thrown instead of
    /// `CancellationError`, so that cancellation does not hide it.
    private static func checkCancellation(rethrowing failure: (any Error)?) throws {
        if Task.isCancelled {
            throw failure ?? CancellationError()
        }
    }
}

/// Records that Slack has ended a streaming message's session: the one terminal state every request path checks.
///
/// The message's ``StreamingMessage/Delivery`` raises it when the input throws ``StreamingMessage/SessionStopped``
/// or the app marks the delivery. Raising it cannot withdraw a call already in progress; it makes ``check()`` throw
/// before the next one, and it ends ``sleep(for:)`` waits.
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
/// bounded batches from what accumulated between calls. Adjacent markdown and adjacent blocks merge up to Slack's limits.
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

    /// Stops taking parts and discards everything buffered, once delivery has ended without sending them.
    func close() {
        isClosed = true
        parts = []
    }

    /// Drops the buffered parts, takes no more, and ends the input, because Slack has ended the session.
    ///
    /// A sender waiting in ``next()`` wakes and takes an empty final batch, after which its stop signal check
    /// throws. The input's own end, which may come later, is then ignored.
    func discard() {
        isClosed = true
        parts = []
        finish(throwing: StreamingMessage.SessionStopped())
    }

    /// Waits until parts are available, the input has ended, or the sender is cancelled, then takes one
    /// bounded request. A finished input is final only when its remaining parts have been drained.
    func next() async -> Batch {
        while parts.isEmpty, !isFinished, !Task.isCancelled {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    precondition(waiter == nil, "PartBuffer supports one sender")
                    waiter = continuation
                }
            } onCancel: {
                // The handler is synchronous and cannot reach the actor's state, so it wakes the sender from a
                // task rather than guarding the waiter with a lock. If it runs before the sender suspends, this
                // task waits for the actor and resumes the waiter once it is stored. It makes no request and
                // nothing awaits it.
                Task { await self.resumeWaiter() }
            }
        }
        return take(isFinal: isFinished)
    }

    private func take(isFinal: Bool) -> Batch {
        let taken = Self.requestBatches(parts)[0]
        parts.removeFirst(taken.count)
        let final = isFinal && parts.isEmpty
        return Batch(parts: taken, isFinal: final, failure: final ? failure : nil)
    }

    /// Limits the aggregate markdown and blocks in each request, including non-adjacent chunks.
    /// Input parts have already been split to the individual chunk limits by `add`.
    static func requestBatches(_ parts: [StreamingMessage.Part]) -> [[StreamingMessage.Part]] {
        var batches: [[StreamingMessage.Part]] = []
        var batch: [StreamingMessage.Part] = []
        var markdown = 0
        var blocks = 0
        for part in parts {
            let textCount: Int
            let blockCount: Int
            switch part {
            case let .markdown(text):
                textCount = text.utf16.count
                blockCount = 0
            case let .blocks(values):
                textCount = 0
                blockCount = values.count
            case .task, .plan:
                textCount = 0
                blockCount = 0
            }
            if !batch.isEmpty, markdown + textCount > markdownLimit || blocks + blockCount > blocksLimit {
                batches.append(batch)
                batch = []
                markdown = 0
                blocks = 0
            }
            batch.append(part)
            markdown += textCount
            blocks += blockCount
        }
        batches.append(batch)
        return batches
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
        guard !text.isEmpty else { return }
        // Count UTF-16 units conservatively: Swift's Character count treats an emoji sequence as
        // one character, while Slack can count its individual code points or UTF-16 units.
        var chunk = ""
        var count = 0
        if case let .markdown(previous)? = parts.last, previous.utf16.count < Self.markdownLimit {
            parts.removeLast()
            chunk = previous
            count = previous.utf16.count
        }
        for scalar in text.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            if count + width > Self.markdownLimit {
                parts.append(.markdown(chunk))
                chunk = ""
                count = 0
            }
            chunk.unicodeScalars.append(scalar)
            count += width
        }
        if !chunk.isEmpty {
            parts.append(.markdown(chunk))
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
