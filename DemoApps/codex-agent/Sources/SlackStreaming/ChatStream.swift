import SlackKit

/// Sends an `AsyncStream` of chunks to Slack as one streaming message.
///
/// Producers yield chunks as fast as they come, for example one text delta per LLM token, and finish the
/// stream when the reply is complete:
///
/// ```swift
/// let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
/// Task {
///     for try await token in llm.tokens(for: prompt) {
///         continuation.yield(.markdownText(token))
///     }
///     continuation.finish()
/// }
/// try await ChatStream(transport: transport).send(chunks, blocks: feedbackBlocks)
/// ```
///
/// ``send(_:blocks:sessionStatus:)`` starts the message with the first chunks, sends whatever arrived during
/// each request with the next `chat.appendStream` call, waits at least `minimumInterval` between calls, and
/// sends the chunks left when the stream finishes with `chat.stopStream`. Cancelling the task that calls
/// `send` ends the input like finishing it, so the message is still stopped. If a call fails partway, the
/// message is stopped before `send` throws, so it does not stay streaming.
public struct ChatStream: Sendable {
    private let transport: any ChatStreamTransport
    private let minimumInterval: Duration

    /// - Parameters:
    ///   - minimumInterval: The shortest time between two calls. `chat.appendStream` is a Tier 4 method
    ///     (100+ per minute).
    public init(transport: any ChatStreamTransport, minimumInterval: Duration = .seconds(1)) {
        self.transport = transport
        self.minimumInterval = minimumInterval
    }

    /// Streams `chunks` into one message and stops it once `chunks` finishes.
    ///
    /// - Parameters:
    ///   - blocks: Blocks rendered at the bottom of the finished message.
    ///   - sessionStatus: The agent session's status after the stream stops. Slack defaults to `active`.
    /// - Returns: The message's `ts`.
    @discardableResult
    public func send(
        _ chunks: AsyncStream<StreamChunk>,
        blocks: [Block]? = nil,
        sessionStatus: String? = nil,
    ) async throws -> String {
        let buffer = ChunkBuffer()
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                for await chunk in chunks {
                    await buffer.append(chunk)
                }
                await buffer.finish()
                return nil
            }
            group.addTask {
                try await deliver(from: buffer, blocks: blocks, sessionStatus: sessionStatus)
            }
            // If delivery fails, cancelling the group ends the input loop, which stops consuming `chunks`.
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let ts = result {
                    return ts
                }
            }
            preconditionFailure("delivery returns a ts or throws")
        }
    }

    private func deliver(from buffer: ChunkBuffer, blocks: [Block]?, sessionStatus: String?) async throws -> String {
        var ts: String?
        let remaining: [StreamChunk]
        do {
            remaining = try await stream(from: buffer, ts: &ts)
        } catch {
            // Stop the message so it does not stay streaming, then report the failure.
            if let ts {
                try? await Self.uncancellable { [transport] in
                    try await transport.stop(ts: ts, chunks: [], blocks: blocks, sessionStatus: sessionStatus)
                }
            }
            throw error
        }

        // The final calls run even when the caller was cancelled, because cancelling must still stop the
        // message, and a real HTTP transport abandons requests made from a cancelled task.
        return try await Self.uncancellable { [transport, ts] in
            var chunks = remaining
            let messageTs: String
            if let ts {
                messageTs = ts
            } else {
                // A stream needs content to start; stop it with the blocks alone if there is nothing else.
                messageTs = try await transport.start(chunks: chunks.isEmpty ? [.markdownText(" ")] : chunks)
                chunks = []
            }
            try await transport.stop(ts: messageTs, chunks: chunks, blocks: blocks, sessionStatus: sessionStatus)
            return messageTs
        }
    }

    /// Starts and appends to the message until the input finishes, and returns the chunks left for the stop.
    private func stream(from buffer: ChunkBuffer, ts: inout String?) async throws -> [StreamChunk] {
        while true {
            var batch = await buffer.next()
            if Task.isCancelled, !batch.isFinal {
                // Cancelling ends the input: everything left goes out with the final call.
                await buffer.finish()
                batch = await .init(chunks: batch.chunks + buffer.next().chunks, isFinal: true)
            }
            if batch.isFinal {
                return batch.chunks
            }

            if let ts {
                try await transport.append(ts: ts, chunks: batch.chunks)
            } else {
                ts = try await transport.start(chunks: batch.chunks)
            }
            // A cancelled sleep returns early, and the next batch is the final one.
            try? await Task.sleep(for: minimumInterval)
        }
    }

    /// Runs `operation` in a new task, which does not inherit the caller's cancellation.
    private static func uncancellable<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        try await Task { try await operation() }.value
    }
}
