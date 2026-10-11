/// A one-turn stop signal. The producer and stop waiter are children of `run`, and both finish before it returns.
/// Stopping this scope leaves the caller free to drain the produced parts and finish the Slack message.
struct TurnProducer: Sendable {
    private let stopped: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stopped, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func stop() {
        continuation.finish()
    }

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await operation() }
            group.addTask {
                for await _ in stopped {}
            }
            // Production finishing also cancels the waiter, so a normal turn needs no stop signal.
            _ = await group.next()
            group.cancelAll()
        }
    }
}
