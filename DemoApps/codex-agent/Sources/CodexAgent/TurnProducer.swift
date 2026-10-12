import Foundation
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
        struct State {
            var reason: Reason?
            var waiters: [UUID: AsyncStream<Void>.Continuation] = [:]
        }
        let state = Mutex(State())

        func stop(_ reason: Reason) {
            let waiters = state.withLock { state in
                if reason == .sessionStopped || state.reason == nil {
                    state.reason = reason
                }
                let waiters = Array(state.waiters.values)
                state.waiters.removeAll()
                return waiters
            }
            for waiter in waiters { waiter.finish() }
        }
    }

    private let signal = Signal()

    /// Why the turn stopped, or `nil` while it runs. A session stop replaces an earlier local cancellation.
    var reason: Reason? {
        signal.state.withLock(\.reason)
    }

    var isSessionStopped: Bool {
        reason == .sessionStopped
    }

    /// Cancels production and leaves the caller free to finish the message.
    func cancel() {
        signal.stop(.cancelled)
    }

    /// Records that Slack ended the session's stream and cancels production.
    func stopSession() {
        signal.stop(.sessionStopped)
    }

    func waitForStop() async {
        // Cancelling one consumer of a shared AsyncStream terminates the stream for every consumer.
        // Each waiter owns a stream so question cleanup cannot stop the producing task.
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let alreadyStopped = signal.state.withLock { state in
            guard state.reason == nil else { return true }
            state.waiters[id] = continuation
            return false
        }
        if alreadyStopped { continuation.finish() }
        defer {
            _ = signal.state.withLock { $0.waiters.removeValue(forKey: id) }
            continuation.finish()
        }
        for await _ in stream {}
    }

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await operation() }
                group.addTask { await waitForStop() }
                // Production finishing also cancels the waiter, so a normal turn needs no stop signal.
                _ = await group.next()
                group.cancelAll()
            }
        } onCancel: {
            cancel()
        }
    }
}
