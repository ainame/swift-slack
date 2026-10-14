import Foundation
import Logging
import Synchronization

/// Runs each Slack agent session as a Codex thread, through the `codex app-server` that swift-codex launches.
/// Sessions are keyed by ``SessionKey``, so a Slack thread or DM thread gets its own Codex thread, and so does
/// a Slack Code channel, whose messages and thread replies all continue one conversation.
///
/// swift-codex allows one active turn per `Codex` instance, so every session gets its own instance and
/// app-server process. A session idle for `idleTimeout` closes its process and keeps the thread ID, so the
/// next message resumes the conversation in a new process.
actor CodexRuntime {
    struct Settings: Sendable {
        var codexPath: String?
        var model: String?
        var workspace: String
        var sessionWorkspaces: String?
        var writable = false
        var gitWritableRoots: WorktreeGitRoots?
        var sourceRepository: String?
        var idleTimeout: Duration = .seconds(600)
    }

    private let settings: Settings
    private let logger: Logger
    private let workspaces: SessionWorkspaces?
    private nonisolated let controls = Mutex<[SessionKey: TurnControl]>([:])
    private var sessions: [SessionKey: CodexSession] = [:]
    /// Threads of closed sessions, resumed when the session continues.
    private var threadIDs: [SessionKey: String] = [:]
    private var idleTimers: [SessionKey: Task<Void, Never>] = [:]

    init(settings: Settings, logger: Logger) throws {
        self.settings = settings
        self.logger = logger
        workspaces = try settings.sessionWorkspaces.map { try SessionWorkspaces(source: settings.workspace, root: $0) }
    }

    nonisolated func respond(
        to prompt: String,
        in session: SessionKey,
        tools: SlackAgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let control = TurnControl(session: session.description)
            controls.withLock { $0[session] = control }
            // The turn runs in its own task so that stopping it can interrupt Codex and still read the turn
            // to its end. Otherwise its remaining notifications would reach the session's next turn.
            Task {
                defer {
                    controls.withLock { controls in
                        if controls[session] === control {
                            controls[session] = nil
                        }
                    }
                }
                do {
                    try await self.run(
                        prompt: prompt,
                        in: session,
                        tools: tools,
                        control: control,
                        continuation: continuation,
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    control.cancel()
                }
            }
        }
    }

    nonisolated func stop(in session: SessionKey) {
        controls.withLock { $0[session] }?.cancel()
    }

    private func run(
        prompt: String,
        in key: SessionKey,
        tools: SlackAgentTools,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        guard !control.isCancelled else { return }
        idleTimers.removeValue(forKey: key)?.cancel()
        var scoped = settings
        var conversationID = threadIDs[key]
        if case .codeChannel = key, let workspaces {
            // Revalidate every turn, even when the app-server is still alive.
            let workspace = try await workspaces.allocation(for: key)
            scoped.workspace = workspace.path
            scoped.writable = true
            scoped.gitWritableRoots = workspace.gitWritableRoots
            scoped.sourceRepository = workspace.repository
            conversationID = workspace.conversationID
            do { try await tools.showWorkspace(workspace) }
            catch { logger.warning("Could not show workspace context", metadata: ["session": "\(key)", "error": "\(error)"]) }
        }
        let session: CodexSession
        if let existing = sessions[key] {
            session = existing
        } else {
            let store = workspaces
            session = CodexSession(
                settings: scoped,
                session: key,
                threadID: conversationID,
                logger: logger,
                saveConversation: { id in
                    if case .codeChannel = key {
                        try await store?.saveConversation(id, for: key)
                    }
                },
            )
        }
        sessions[key] = session
        defer { scheduleIdleClose(key, session: session) }
        guard !control.isCancelled else { return }
        try await session.run(prompt: prompt, tools: tools, control: control, continuation: continuation)
        await control.waitForInterruption()
    }

    private func scheduleIdleClose(_ key: SessionKey, session: CodexSession) {
        idleTimers[key]?.cancel()
        idleTimers[key] = Task {
            try? await Task.sleep(for: settings.idleTimeout)
            guard !Task.isCancelled else { return }
            await self.close(key, session: session)
        }
    }

    private func close(_ key: SessionKey, session: CodexSession) async {
        guard sessions[key] === session, await !session.isRunning else { return }
        sessions[key] = nil
        idleTimers[key] = nil
        threadIDs[key] = await session.close()
        logger.info("Closed idle Codex session", metadata: ["session": "\(key)"])
    }
}
