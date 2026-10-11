import Codex
import Logging
import SlackStreaming

/// Runs each Slack agent session as a Codex thread, through the `codex app-server` that swift-codex launches.
///
/// swift-codex allows one active turn per `Codex` instance, so every session gets its own instance and
/// app-server process. Sessions stay open until the app exits.
actor CodexBackend: AgentBackend {
    struct Settings: Sendable {
        var codexPath: String?
        var model: String?
        var workspace: String
    }

    private let settings: Settings
    private let logger: Logger
    private var sessions: [SessionKey: CodexSession] = [:]

    init(settings: Settings, logger: Logger) {
        self.settings = settings
        self.logger = logger
    }

    nonisolated func respond(to prompt: String, in session: SessionKey) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let codexSession = await self.session(for: session)
                    try await codexSession.run(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func interrupt(_ session: SessionKey) async {
        await sessions[session]?.interrupt()
    }

    private func session(for key: SessionKey) -> CodexSession {
        if let session = sessions[key] {
            return session
        }
        let session = CodexSession(settings: settings, logger: logger)
        sessions[key] = session
        return session
    }
}

private actor CodexSession {
    private let settings: CodexBackend.Settings
    private let logger: Logger
    private var codex: Codex?
    private var thread: CodexThread?
    private var activeTurn: CodexTurnHandle?

    init(settings: CodexBackend.Settings, logger: Logger) {
        self.settings = settings
        self.logger = logger
    }

    func run(prompt: String, continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation) async throws {
        let thread = try await prepareThread()
        let handle = try await thread.turn(prompt, options: TurnOptions(summary: .concise))
        activeTurn = handle
        defer { activeTurn = nil }

        var translator = NotificationTranslator(turnID: handle.id)
        for try await notification in try await handle.stream() {
            for event in try translator.events(for: notification) {
                continuation.yield(event)
            }
        }
    }

    func interrupt() async {
        guard let activeTurn else { return }
        do {
            _ = try await activeTurn.interrupt()
        } catch {
            logger.warning("Failed to interrupt Codex turn", metadata: ["error": "\(error)"])
        }
    }

    private func prepareThread() async throws -> CodexThread {
        if let thread {
            return thread
        }
        let codex = try await Codex(
            config: CodexConfig(codexPathOverride: settings.codexPath, clientName: "swift-slack-codex-agent"),
            logger: logger,
        )
        self.codex = codex
        let thread = try await codex.startThread(options: ThreadOptions(
            approvalPolicy: .never,
            cwd: settings.workspace,
            developerInstructions: """
            You are answering a person in Slack. Keep answers short and use Markdown that Slack renders: \
            bold, italics, lists, inline code, and fenced code blocks. Do not use tables or headings.
            """,
            model: settings.model,
            sandboxPreset: .readOnly,
        ))
        self.thread = thread
        return thread
    }
}

/// Maps Codex app-server notifications onto agent events.
struct NotificationTranslator {
    enum Failure: Error, CustomStringConvertible {
        case turnFailed(String)

        var description: String {
            switch self {
            case let .turnFailed(message): message
            }
        }
    }

    let turnID: String
    private var lastMessageItemID: String?

    init(turnID: String) {
        self.turnID = turnID
    }

    mutating func events(for notification: CodexNotification) throws -> [AgentEvent] {
        guard notification.turnID == nil || notification.turnID == turnID else {
            return []
        }

        switch notification.payload {
        case let .agentMessageDelta(payload):
            // Separate the messages Codex writes between tool calls into paragraphs.
            let separator = lastMessageItemID.map { $0 == payload.itemId ? "" : "\n\n" } ?? ""
            lastMessageItemID = payload.itemId
            return [.text(separator + payload.delta)]
        case let .itemStarted(payload):
            return task(for: payload.item).map { [.task($0)] } ?? []
        case let .itemCompleted(payload):
            return task(for: payload.item).map { [.task($0)] } ?? []
        case let .turnCompleted(payload) where payload.turn.status == .failed:
            throw Failure.turnFailed(payload.turn.error?.message ?? "Codex turn failed")
        case let .error(payload):
            throw Failure.turnFailed(payload.error.message)
        default:
            return []
        }
    }

    private func task(for item: ThreadItem) -> TaskUpdate? {
        switch item {
        case let .commandExecution(command):
            TaskUpdate(
                id: command.id,
                title: "Run `\(command.command)`",
                status: status(command.status),
                output: command.aggregatedOutput.flatMap { $0.isEmpty ? nil : String($0.suffix(200)) },
            )
        case let .webSearch(search):
            TaskUpdate(id: search.id, title: "Search the web for \"\(search.query)\"", status: .complete)
        case let .fileChange(change):
            TaskUpdate(
                id: change.id,
                title: "Edit \(change.changes.count) file(s)",
                status: status(change.status),
                details: change.changes.map(\.path).joined(separator: "\n"),
            )
        case let .mcpToolCall(call):
            TaskUpdate(id: call.id, title: "Call \(call.server)/\(call.tool)", status: status(call.status))
        case let .reasoning(reasoning):
            (reasoning.summary ?? []).isEmpty
                ? nil
                : TaskUpdate(
                    id: reasoning.id,
                    title: "Think",
                    status: .complete,
                    details: reasoning.summary?.joined(separator: "\n"),
                )
        default:
            nil
        }
    }

    private func status(_ status: CommandExecutionStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }

    private func status(_ status: PatchApplyStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }

    private func status(_ status: McpToolCallStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }
}
