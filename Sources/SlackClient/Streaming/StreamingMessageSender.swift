#if WebAPI_Chat
import SlackBlockKit

/// The three Web API calls behind a streaming message. ``StreamingMessageSender`` decides when to make them.
protocol StreamingMessageTransport: Sendable {
    /// Calls `chat.startStream` and returns the message's `ts`.
    func start(chunks: [StreamingMessage.Part]) async throws -> String
    /// Calls `chat.appendStream`.
    func append(ts: String, chunks: [StreamingMessage.Part]) async throws
    /// Calls `chat.stopStream`.
    func stop(ts: String, chunks: [StreamingMessage.Part], blocks: [Block]?) async throws
}

/// Sends a sequence of parts as one streaming message.
///
/// The caller's task reads the sequence into a ``PartBuffer``, and a child task sends whatever the buffer holds
/// with each call. Reading in the caller's task keeps the sequence in the caller's isolation, so it need not be
/// `Sendable`.
struct StreamingMessageSender<Transport: StreamingMessageTransport>: Sendable {
    let transport: Transport
    let blocks: [Block]?
    let minimumInterval: Duration

    func send<Parts: AsyncSequence>(
        _ parts: Parts,
        isolation: isolated (any Actor)? = #isolation,
    ) async throws -> String where Parts.Element == StreamingMessage.Part {
        let buffer = PartBuffer()
        return try await withThrowingTaskGroup(of: String.self, returning: String.self, isolation: isolation) { group in
            group.addTask {
                try await deliver(from: buffer)
            }
            do {
                for try await part in parts {
                    // The buffer closes when delivery ends early, after a failed call or a cancellation.
                    guard await buffer.append(part) else { break }
                }
                await buffer.finish(throwing: nil)
            } catch {
                await buffer.finish(throwing: error)
            }
            guard let ts = try await group.next() else {
                preconditionFailure("delivery returns a ts or throws")
            }
            return ts
        }
    }

    private func deliver(from buffer: PartBuffer) async throws -> String {
        var ts: String?
        let ending: PartBuffer.Batch
        do {
            ending = try await stream(from: buffer, ts: &ts)
        } catch {
            await buffer.close()
            // Stop the message so it does not stay streaming; the failed call may have carried the last parts.
            if let ts {
                try? await Self.uncancellable { [transport] in
                    try await transport.stop(ts: ts, chunks: [], blocks: nil)
                }
            }
            throw error
        }
        if let failure = ending.failure, ts == nil, ending.parts.isEmpty {
            // The input failed before it produced anything, so there is no message to post.
            throw failure
        }

        // The closing calls run even when the caller was cancelled, because cancelling must still stop the
        // message, and HTTP transports abandon requests made from a cancelled task.
        let messageTs = try await Self.uncancellable { [transport, blocks, ts] in
            var chunks = ending.parts
            let messageTs: String
            if let ts {
                messageTs = ts
            } else {
                // A stream needs content to start; start with a space when nothing else came.
                messageTs = try await transport.start(chunks: chunks.isEmpty ? [.markdown(" ")] : chunks)
                chunks = []
            }
            try await transport.stop(ts: messageTs, chunks: chunks, blocks: blocks)
            return messageTs
        }
        if let failure = ending.failure {
            throw failure
        }
        return messageTs
    }

    /// Starts and appends to the message until the input ends, and returns the final batch for the stop call.
    private func stream(from buffer: PartBuffer, ts: inout String?) async throws -> PartBuffer.Batch {
        while true {
            var batch = await buffer.next()
            if !batch.isFinal, Task.isCancelled {
                // Cancelling ends the input: everything buffered goes out with the stop call.
                batch = await buffer.close()
            }
            if batch.isFinal {
                return batch
            }

            if let ts {
                try await transport.append(ts: ts, chunks: batch.parts)
            } else {
                ts = try await transport.start(chunks: batch.parts)
            }
            // A cancelled sleep returns early, and the next batch is the final one.
            try? await Task.sleep(for: minimumInterval)
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
    func append(_ part: StreamingMessage.Part) -> Bool {
        guard !isClosed else { return false }
        switch part {
        case let .markdown(text):
            appendMarkdown(text)
        case let .blocks(blocks):
            appendBlocks(blocks)
        case .task, .plan:
            parts.append(part)
        }
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

    /// Stops taking parts and returns everything buffered as the final batch.
    @discardableResult
    func close() -> Batch {
        isClosed = true
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
