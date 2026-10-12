import Synchronization

/// A one-turn stop signal. The producer and stop waiter are children of `run`, and both finish before it returns.
///
/// A turn stops for one of two reasons, recorded in ``reason``. ``cancel()`` is the app's own graceful stop:
/// the message is still streaming, so the caller drains the produced parts and finishes it. ``stopSession()``
/// records that Slack ended the session's stream, after which the turn must not call Slack again.
struct TurnProducer: Sendable {
    enum Reason: Sendable, Equatable {
        /// The app cancelled production, such as after a failed delivery or when its caller was cancelled.
        case cancelled
        /// Slack ended the session's stream, as the stop button does.
        case sessionStopped
    }

    private final class Signal: Sendable {
        let reason = Mutex<Reason?>(nil)
        let stopped: AsyncStream<Void>
        let continuation: AsyncStream<Void>.Continuation

        init() {
            (stopped, continuation) = AsyncStream.makeStream(of: Void.self)
        }
    }

    private let signal = Signal()

    /// Why the turn stopped, or `nil` while it runs. A session stop replaces an earlier local cancellation.
    var reason: Reason? {
        signal.reason.withLock(\.self)
    }

    var isSessionStopped: Bool {
        reason == .sessionStopped
    }

    /// Cancels production and leaves the caller free to finish the message.
    func cancel() {
        signal.reason.withLock { $0 = $0 ?? .cancelled }
        signal.continuation.finish()
    }

    /// Records that Slack ended the session's stream and cancels production.
    func stopSession() {
        signal.reason.withLock { $0 = .sessionStopped }
        signal.continuation.finish()
    }

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await operation() }
            group.addTask { [signal] in
                for await _ in signal.stopped {}
            }
            // Production finishing also cancels the waiter, so a normal turn needs no stop signal.
            _ = await group.next()
            group.cancelAll()
        }
    }
}
