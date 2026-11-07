import Codex
import Logging
import Synchronization

/// Connects a stopped Slack turn to the Codex turn it started, whichever happens first.
final class TurnControl: Sendable {
    private struct State {
        var isCancelled = false
        var interrupt: (@Sendable () async throws -> Void)?
        var request: Task<Void, Never>?
    }

    private let state = Mutex(State())
    private let logger: Logger

    init(session: String? = nil) {
        var logger = Logger(label: "codex-agent.stop")
        if let session {
            logger[metadataKey: "session"] = "\(session)"
        }
        self.logger = logger
    }

    var isCancelled: Bool {
        state.withLock(\.isCancelled)
    }

    func cancel() {
        state.withLock { state in
            state.isCancelled = true
            requestIfNeeded(&state)
        }
    }

    func attach(_ handle: CodexTurnHandle) {
        attachInterruption { _ = try await handle.interrupt() }
    }

    /// Registration and cancellation share a lock: stopping before turn/start returns still interrupts it.
    func attachInterruption(_ operation: @escaping @Sendable () async throws -> Void) {
        state.withLock { state in
            state.interrupt = operation
            requestIfNeeded(&state)
        }
    }

    func waitForInterruption() async {
        await state.withLock { $0.request }?.value
    }

    private func requestIfNeeded(_ state: inout State) {
        guard state.isCancelled, state.request == nil, let interrupt = state.interrupt else { return }
        let logger = logger
        state.request = Task {
            logger.info("Requesting Codex interruption")
            do {
                try await interrupt()
                logger.info("Codex interruption acknowledged")
            } catch {
                logger.error("Codex interruption failed", metadata: ["error": "\(error)"])
            }
        }
    }
}
