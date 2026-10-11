/// Collects chunks while a request is in flight so the next request sends them together.
///
/// A producer can yield a text delta per token, but `chat.appendStream` is rate limited, so ``ChatStream``
/// reads the buffer only between requests: whatever arrived in the meantime goes out as one batch, with
/// adjacent markdown merged into one chunk.
actor ChunkBuffer {
    struct Batch: Equatable {
        var chunks: [StreamChunk]
        /// `true` once the input has finished: no chunks follow this batch.
        var isFinal: Bool
    }

    private var chunks: [StreamChunk] = []
    private var isFinished = false
    private var waiter: CheckedContinuation<Void, Never>?

    func append(_ chunk: StreamChunk) {
        if case let .markdownText(text) = chunk,
           case let .markdownText(previous)? = chunks.last,
           previous.count + text.count <= StreamChunk.markdownTextLimit {
            chunks[chunks.count - 1] = .markdownText(previous + text)
        } else {
            chunks.append(chunk)
        }
        resumeWaiter()
    }

    func finish() {
        isFinished = true
        resumeWaiter()
    }

    /// Waits until chunks are available or the input has finished, then takes everything buffered.
    func next() async -> Batch {
        while chunks.isEmpty, !isFinished {
            await withCheckedContinuation { waiter = $0 }
        }
        defer { chunks = [] }
        return Batch(chunks: chunks, isFinal: isFinished)
    }

    private func resumeWaiter() {
        waiter?.resume()
        waiter = nil
    }
}
