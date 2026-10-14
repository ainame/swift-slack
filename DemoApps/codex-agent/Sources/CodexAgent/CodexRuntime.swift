import Foundation
import Logging

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
    private var controls: [SessionKey: (producer: TurnProducer, control: TurnControl)] = [:]
    private var sessions: [SessionKey: CodexSession] = [:]
    /// Threads of closed sessions, resumed when the session continues.
    private var threadIDs: [SessionKey: String] = [:]
    private var closing: [SessionKey: Task<Void, Never>] = [:]
    private var idleTimers: [SessionKey: Task<Void, Never>] = [:]

    init(settings: Settings, logger: Logger) throws {
        self.settings = settings
        self.logger = logger
        workspaces = try settings.sessionWorkspaces.map { try SessionWorkspaces(source: settings.workspace, root: $0) }
    }

    func respond(
        to prompt: String,
        in session: SessionKey,
        tools: SlackAgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, any Error>.makeStream()
        // The caller may have stopped while awaiting this actor. Do not register or launch that turn.
        guard tools.producer.reason == nil, !Task.isCancelled else {
            continuation.finish()
            return stream
        }
        let control = TurnControl(session: session.description)
        controls[session] = (tools.producer, control)
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                control.cancel()
            }
        }
        // Register before scheduling work. Stop can interrupt Codex while this task awaits its output;
        // keep reading the interrupted turn to its end so notifications cannot reach the next turn.
        Task {
            defer {
                if controls[session]?.control === control {
                    controls[session] = nil
                }
            }
            do {
                try await run(
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
        return stream
    }

    func stop(in session: SessionKey, producer: TurnProducer) {
        guard let registered = controls[session], registered.producer.isSameTurn(as: producer) else { return }
        registered.control.cancel()
    }

    private func run(
        prompt: String,
        in key: SessionKey,
        tools: SlackAgentTools,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        guard !control.isCancelled, tools.producer.reason == nil else { return }
        idleTimers.removeValue(forKey: key)?.cancel()
        // Shutdown publishes the thread ID before completing; a new turn must wait before resuming it.
        await closing[key]?.value
        guard !control.isCancelled, tools.producer.reason == nil else { return }
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
        guard !control.isCancelled, tools.producer.reason == nil else { return }
        try await session.run(prompt: prompt, tools: tools, control: control, continuation: continuation)
        await control.waitForInterruption()
    }

    private func scheduleIdleClose(_ key: SessionKey, session: CodexSession) {
        idleTimers[key]?.cancel()
        idleTimers[key] = Task {
            try? await Task.sleep(for: settings.idleTimeout)
            guard !Task.isCancelled else { return }
            self.close(key, session: session)
        }
    }

    private func close(_ key: SessionKey, session: CodexSession) {
        // Controls include registered/queued turns, not just the session's currently executing turn.
        // Reserve closing without an actor hop so a new turn cannot reuse a process being shut down.
        guard !Task.isCancelled, sessions[key] === session, controls[key] == nil else { return }
        sessions[key] = nil
        idleTimers[key] = nil
        closing[key] = Task {
            threadIDs[key] = await session.close()
            closing[key] = nil
            logger.info("Closed idle Codex session", metadata: ["session": "\(key)"])
        }
    }
}
