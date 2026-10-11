import Codex
import Foundation
import Logging
import SlackStreaming
import Synchronization

/// Runs each Slack agent session as a Codex thread, through the `codex app-server` that swift-codex launches.
///
/// swift-codex allows one active turn per `Codex` instance, so every session gets its own instance and
/// app-server process. A session idle for `idleTimeout` closes its process and keeps the thread ID, so the
/// next message resumes the conversation in a new process.
actor CodexBackend: AgentBackend {
    struct Settings: Sendable {
        var codexPath: String?
        var model: String?
        var workspace: String
        var idleTimeout: Duration = .seconds(600)
    }

    private let settings: Settings
    private let logger: Logger
    private var sessions: [SessionKey: CodexSession] = [:]
    /// Threads of closed sessions, resumed when the session continues.
    private var threadIDs: [SessionKey: String] = [:]
    private var idleTimers: [SessionKey: Task<Void, Never>] = [:]

    init(settings: Settings, logger: Logger) {
        self.settings = settings
        self.logger = logger
    }

    nonisolated func respond(to prompt: String, in session: SessionKey) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let control = TurnControl()
            // The turn runs in its own task so that stopping it can interrupt Codex and still read the turn
            // to its end. Otherwise its remaining notifications would reach the session's next turn.
            Task {
                do {
                    try await self.run(prompt: prompt, in: session, control: control, continuation: continuation)
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

    private func run(
        prompt: String,
        in key: SessionKey,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        idleTimers.removeValue(forKey: key)?.cancel()
        let session = sessions[key] ?? CodexSession(settings: settings, threadID: threadIDs[key], logger: logger)
        sessions[key] = session
        defer { scheduleIdleClose(key, session: session) }
        try await session.run(prompt: prompt, control: control, continuation: continuation)
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

/// Connects a stopped Slack turn to the Codex turn it started, whichever happens first.
private final class TurnControl: Sendable {
    private struct State {
        var isCancelled = false
        var handle: CodexTurnHandle?
    }

    private let state = Mutex(State())

    var isCancelled: Bool {
        state.withLock(\.isCancelled)
    }

    func cancel() {
        let handle = state.withLock { state in
            state.isCancelled = true
            return state.handle
        }
        if let handle {
            Task { _ = try? await handle.interrupt() }
        }
    }

    /// Records the started turn and interrupts it if the Slack turn was already stopped.
    func attach(_ handle: CodexTurnHandle) {
        let isCancelled = state.withLock { state in
            state.handle = handle
            return state.isCancelled
        }
        if isCancelled {
            Task { _ = try? await handle.interrupt() }
        }
    }
}

private actor CodexSession {
    private let settings: CodexBackend.Settings
    private let logger: Logger
    private var codex: Codex?
    private var thread: CodexThread?
    private var threadID: String?
    /// The previous turn. Turns run one at a time, including the rest of an interrupted one.
    private var lastTurn: Task<Void, any Error>?
    private(set) var isRunning = false

    init(settings: CodexBackend.Settings, threadID: String?, logger: Logger) {
        self.settings = settings
        self.threadID = threadID
        self.logger = logger
    }

    func run(
        prompt: String,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        let previous = lastTurn
        let turn = Task {
            _ = await previous?.result
            try await self.execute(prompt: prompt, control: control, continuation: continuation)
        }
        lastTurn = turn
        try await turn.value
    }

    /// Closes the app-server process and returns the thread ID to resume later.
    func close() async -> String? {
        await codex?.close()
        codex = nil
        thread = nil
        return threadID
    }

    private func execute(
        prompt: String,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        isRunning = true
        defer { isRunning = false }
        let thread = try await prepareThread()
        guard !control.isCancelled else { return }

        let handle = try await thread.turn(prompt, options: TurnOptions(summary: .concise))
        control.attach(handle)

        // Read to turn/completed even after a stop; yielding to a terminated stream does nothing.
        var translator = NotificationTranslator(turnID: handle.id)
        for try await notification in try await handle.stream() {
            for event in translator.events(for: notification) {
                continuation.yield(event)
            }
        }
        if let failure = translator.failure {
            throw failure
        }
    }

    /// The variables Codex needs to run and find its login in `~/.codex`. Without an explicit environment,
    /// swift-codex passes the app's own, including any exported Slack tokens, and Codex can print it.
    private static func childEnvironment() -> [String: String] {
        let names = ["PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "TERM", "CODEX_HOME"]
        let environment = ProcessInfo.processInfo.environment
        return environment.filter { names.contains($0.key) }
    }

    private func prepareThread() async throws -> CodexThread {
        if let thread {
            return thread
        }
        let codex = try await Codex(
            config: CodexConfig(
                codexPathOverride: settings.codexPath,
                environment: Self.childEnvironment(),
                clientName: "swift-slack-codex-agent",
                dynamicToolCallHandler: CardsTool.handle,
            ),
            logger: logger,
        )
        self.codex = codex
        var options = ThreadOptions(
            approvalPolicy: .never,
            cwd: settings.workspace,
            developerInstructions: """
            You are answering a person in Slack. Keep answers short and use Markdown that Slack renders: \
            bold, italics, lists, inline code, and fenced code blocks. Do not use tables or headings.

            When a few items deserve to stand out, such as files, links, or options to explore next, call \
            the `\(SlackUI.toolName)` tool. The cards appear under your answer, so mention them briefly \
            instead of repeating them.
            """,
            model: settings.model,
            sandboxPreset: .readOnly,
        )
        let thread: CodexThread
        if let threadID {
            // A resumed thread keeps the tools it started with and rejects new definitions.
            thread = try await codex.resumeThread(id: threadID, options: options)
        } else {
            options.dynamicTools = [CardsTool.spec]
            thread = try await codex.startThread(options: options)
        }
        self.thread = thread
        threadID = thread.id
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
    /// The turn's error, kept until the turn completes so the caller still reads it to the end.
    private(set) var failure: Failure?
    private var lastMessageItemID: String?

    init(turnID: String) {
        self.turnID = turnID
    }

    mutating func events(for notification: CodexNotification) -> [AgentEvent] {
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
            if case let .dynamicToolCall(call) = payload.item {
                return CardsTool.cards(from: call).map { [.cards($0)] } ?? []
            }
            return task(for: payload.item).map { [.task($0)] } ?? []
        case let .turnCompleted(payload) where payload.turn.status == .failed:
            failure = failure ?? .turnFailed(payload.turn.error?.message ?? "Codex turn failed")
            return []
        case let .error(payload):
            failure = failure ?? .turnFailed(payload.error.message)
            return []
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
            // The query is empty until the search completes.
            TaskUpdate(
                id: search.id,
                title: search.query.isEmpty ? "Search the web" : "Search the web for \"\(search.query)\"",
                status: .complete,
            )
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

/// The `show_cards` tool registered with Codex, which carries ``SlackUI`` cards from the agent to the app.
enum CardsTool {
    static let spec = DynamicToolSpec.function(.init(
        description: """
        Show cards under your answer in Slack, one per item worth highlighting. Each card may link to an \
        https URL and offer a follow-up question the person can ask with one click.
        """,
        inputSchema: [
            "type": "object",
            "properties": [
                "cards": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 10,
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "maxLength": 150],
                            "subtitle": ["type": "string", "maxLength": 150],
                            "body": ["type": "string", "maxLength": 200, "description": "Slack mrkdwn"],
                            "url": ["type": "string", "pattern": "^https://"],
                            "ask": ["type": "string", "maxLength": 2000, "description": "A follow-up question"],
                        ],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["cards"],
            "additionalProperties": false,
        ],
        name: SlackUI.toolName,
        type: .function,
    ))

    /// Answers a tool call. It only checks the arguments: the cards are read from the completed tool call item,
    /// and handlers must not wait on another request to the same app server.
    @Sendable
    static func handle(_ call: DynamicToolCallParams) async -> DynamicToolCallResponse {
        guard call.tool == SlackUI.toolName, call.namespace == nil else {
            return reply("There is no tool named \(call.tool).", success: false)
        }
        do {
            _ = try SlackUI(arguments: JSONEncoder().encode(call.arguments))
            return reply("The cards will appear under your answer.", success: true)
        } catch let error as SlackUI.InvalidArguments {
            return reply(error.message, success: false)
        } catch {
            return reply("The arguments could not be read.", success: false)
        }
    }

    /// The cards from a successful `show_cards` call.
    static func cards(from call: DynamicToolCallThreadItem) -> SlackUI? {
        guard call.tool == SlackUI.toolName, call.success == true,
              let arguments = try? JSONEncoder().encode(call.arguments) else {
            return nil
        }
        return try? SlackUI(arguments: arguments)
    }

    private static func reply(_ text: String, success: Bool) -> DynamicToolCallResponse {
        DynamicToolCallResponse(contentItems: [.inputText(.init(text: text, type: .inputText))], success: success)
    }
}
