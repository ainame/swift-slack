import Codex
import Foundation
import Logging
import SlackKit
import Synchronization

/// Runs each Slack agent session as a Codex thread, through the `codex app-server` that swift-codex launches.
/// Sessions are keyed by ``SessionKey``, so a Slack thread or DM thread gets its own Codex thread, and so does
/// a Slack Code channel, whose messages and thread replies all continue one conversation.
///
/// swift-codex allows one active turn per `Codex` instance, so every session gets its own instance and
/// app-server process. A session idle for `idleTimeout` closes its process and keeps the thread ID, so the
/// next message resumes the conversation in a new process.
actor CodexBackend: AgentBackend {
    struct Settings: Sendable {
        var codexPath: String?
        var model: String?
        var workspace: String
        var sessionWorkspaces: String?
        var writable = false
        var gitWritableRoots: [String] = []
        var sourceRepository: String?
        var idleTimeout: Duration = .seconds(600)
    }

    private let settings: Settings
    private let logger: Logger
    private let workspaces: SessionWorkspaces?
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
        tools: any AgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let control = TurnControl()
            // The turn runs in its own task so that stopping it can interrupt Codex and still read the turn
            // to its end. Otherwise its remaining notifications would reach the session's next turn.
            Task {
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

    private func run(
        prompt: String,
        in key: SessionKey,
        tools: any AgentTools,
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
    private let session: SessionKey
    private let toolRouter: ToolRouter
    private let logger: Logger
    private let saveConversation: @Sendable (String) async throws -> Void
    private var codex: Codex?
    private var thread: CodexThread?
    private var threadID: String?
    /// The previous turn. Turns run one at a time, including the rest of an interrupted one.
    private var lastTurn: Task<Void, any Error>?
    private(set) var isRunning = false

    init(
        settings: CodexBackend.Settings,
        session: SessionKey,
        threadID: String?,
        logger: Logger,
        saveConversation: @escaping @Sendable (String) async throws -> Void,
    ) {
        self.settings = settings
        self.session = session
        self.threadID = threadID
        self.logger = logger
        self.saveConversation = saveConversation
        toolRouter = ToolRouter(writeWorkspace: settings.writable ? settings.workspace : nil)
    }

    func run(
        prompt: String,
        tools: any AgentTools,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        let previous = lastTurn
        let turn = Task {
            _ = await previous?.result
            try await self.execute(prompt: prompt, tools: tools, control: control, continuation: continuation)
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
        tools: any AgentTools,
        control: TurnControl,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        isRunning = true
        toolRouter.tools = tools
        defer {
            isRunning = false
            toolRouter.tools = nil
        }
        guard !control.isCancelled else { return }
        let thread = try await prepareThread()
        guard !control.isCancelled else { return }

        let handle = try await thread.turn(prompt, options: TurnOptions(summary: .concise))
        control.attach(handle)

        // Read to turn/completed even after a stop; yielding to a terminated stream does nothing.
        var translator = NotificationTranslator(turnID: handle.id)
        for try await notification in try await handle.stream() {
            for event in translator.events(turnID: notification.turnID, payload: notification.payload) {
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
        var child = environment.filter { names.contains($0.key) }
        // Commit housekeeping must not try to rewrite shared packed refs or prune other sessions.
        child["GIT_CONFIG_COUNT"] = "2"
        child["GIT_CONFIG_KEY_0"] = "gc.auto"
        child["GIT_CONFIG_VALUE_0"] = "0"
        child["GIT_CONFIG_KEY_1"] = "maintenance.auto"
        child["GIT_CONFIG_VALUE_1"] = "false"
        return child
    }

    private func prepareThread() async throws -> CodexThread {
        if let thread {
            return thread
        }
        let codex = try await Codex(
            config: CodexConfig(
                codexPathOverride: settings.codexPath,
                launchArgsOverride: WorkspaceSandbox.launchArguments(
                    codexPath: settings.codexPath, workspace: settings.workspace, repository: settings.sourceRepository,
                    stateRoot: settings.sessionWorkspaces.map { URL(filePath: $0).resolvingSymlinksInPath().path },
                    gitRoots: settings.gitWritableRoots, writable: settings.writable,
                ),
                workingDirectory: settings.workspace,
                environment: Self.childEnvironment(),
                clientName: "swift-slack-codex-agent",
                dynamicToolCallHandler: { [toolRouter] call in await toolRouter.handle(call) },
                commandApprovalHandler: { [toolRouter] request in await toolRouter.approveCommand(request) },
                fileChangeApprovalHandler: { [toolRouter] request in await toolRouter.approveFiles(request) },
            ),
            logger: logger,
        )
        self.codex = codex
        var options = ThreadOptions(
            approvalPolicy: settings.writable ? .onRequest : .never,
            cwd: settings.workspace,
            developerInstructions: """
            You are answering a person in Slack. Keep answers short and use Markdown that Slack renders: \
            bold, italics, lists, inline code, and fenced code blocks. Do not use tables or headings.

            When a few items deserve to stand out, such as files, links, or options to explore next, call \
            the `\(SlackUI.toolName)` tool. The cards appear under your answer, so mention them briefly \
            instead of repeating them.

            To ask the person to choose, call `\(AgentToolset.askUser)` and use their answer. Never ask in \
            text and wait: the person cannot reply until your turn ends. Call `\(AgentToolset.readSlack)` when \
            they refer to earlier messages, and `\(AgentToolset.setTitle)` once the topic of the \
            conversation is clear.

            Renaming is optional. If it fails, keep the existing title and continue the task.
            Never create a new channel to recover from a naming failure.
            Keep the current topic branch. Never switch to or commit directly to main/master, modify other
            checkouts, change shared Git config/hooks, or manage worktrees or session state. Git metadata
            outside this worktree's authorized roots requires approval; do not widen permissions yourself.

            \(AgentToolset.sessionInstructions(for: session, writable: settings.writable, writableCodeSessions: settings.sessionWorkspaces != nil))
            """,
            model: settings.model,
            // The process-local named profile carries the narrower Git metadata grants.
            // A legacy sandbox preset/policy would replace it, making .git read-only again.
        )
        let thread: CodexThread
        if let threadID {
            // A resumed thread keeps the tools it started with and rejects new definitions.
            do { thread = try await codex.resumeThread(id: threadID, options: options) }
            catch {
                throw AgentToolError(
                    description: "Cannot resume recorded Codex conversation \(threadID): \(error). Restore the original Codex login/CODEX_HOME and conversation history, then retry. Preserve the worktree and session record; no replacement conversation was started.",
                )
            }
        } else {
            options.dynamicTools = AgentToolset.specs(for: session)
            thread = try await codex.startThread(options: options)
        }
        threadID = thread.id
        // Persist before the first turn: idle close is too late for a process crash or restart.
        try await saveConversation(thread.id)
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
    /// The turn's error, kept until the turn completes so the caller still reads it to the end.
    private(set) var failure: Failure?
    private var lastMessageItemID: String?
    /// Messages that streamed deltas. Codex sometimes sends a message only as a completed item.
    private var streamedMessageIDs: Set<String> = []

    init(turnID: String) {
        self.turnID = turnID
    }

    /// Maps one notification. `turnID` is the notification's turn, or `nil` for one that belongs to none.
    mutating func events(turnID notificationTurnID: String?, payload: CodexNotificationPayload) -> [AgentEvent] {
        guard notificationTurnID == nil || notificationTurnID == turnID else {
            return []
        }

        switch payload {
        case let .agentMessageDelta(payload):
            streamedMessageIDs.insert(payload.itemId)
            return [text(payload.delta, inMessage: payload.itemId)]
        case let .turnDiffUpdated(payload):
            return [.diff(payload.diff)]
        case let .itemCompleted(payload):
            if case let .agentMessage(message) = payload.item, !streamedMessageIDs.contains(message.id) {
                return message.text.isEmpty ? [] : [text(message.text, inMessage: message.id)]
            }
            var events = task(for: payload.item).map { [AgentEvent.task($0)] } ?? []
            if case let .dynamicToolCall(call) = payload.item, let cards = AgentToolset.cards(from: call) {
                events.append(.cards(cards))
            }
            return events
        case let .itemStarted(payload):
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

    /// Separates the messages Codex writes between tool calls into paragraphs.
    private mutating func text(_ text: String, inMessage itemID: String) -> AgentEvent {
        let separator = lastMessageItemID.map { $0 == itemID ? "" : "\n\n" } ?? ""
        lastMessageItemID = itemID
        return .text(separator + text)
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
        case let .dynamicToolCall(call):
            TaskUpdate(id: call.id, title: AgentToolset.title(for: call.tool), status: status(call), details: failureDetails(call))
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

    private func failureDetails(_ call: DynamicToolCallThreadItem) -> String? {
        guard status(call) == .error else { return nil }
        let text = (call.contentItems ?? []).compactMap { item -> String? in
            guard case let .inputText(item) = item else { return nil }
            return item.text
        }.joined(separator: "\n")
        return text.isEmpty ? nil : String(text.prefix(2000))
    }

    private func status(_ call: DynamicToolCallThreadItem) -> TaskUpdate.Status {
        switch call.status {
        case .inProgress: .inProgress
        case .completed where call.success != false: .complete
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

/// Routes Codex's tool calls to the running turn's ``AgentTools``. Codex calls the handler registered when
/// the app-server starts, and a session runs one turn at a time, so the current turn's tools are set here.
final class ToolRouter: Sendable {
    private let current = Mutex<(any AgentTools)?>(nil)
    private let writeWorkspace: String?

    init(writeWorkspace: String? = nil) {
        self.writeWorkspace = writeWorkspace
    }

    private func permits(_ directory: String?) -> Bool {
        guard let writeWorkspace else { return false }
        guard let directory else { return true }
        let root = URL(filePath: writeWorkspace).resolvingSymlinksInPath().path
        let path = URL(filePath: directory, relativeTo: URL(filePath: root, directoryHint: .isDirectory))
            .standardizedFileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }

    func approveCommand(_ request: CommandApprovalRequest) async -> ApprovalDecision {
        guard permits(request.workingDirectory), let tools, let command = request.command, !command.isEmpty else { return .deny }
        let details = [command, request.workingDirectory, request.reason]
            .compactMap(\.self).joined(separator: "\n")
        return await tools.approve(.command(details)) ? .approve : .deny
    }

    func approveFiles(_ request: FileChangeApprovalRequest) async -> ApprovalDecision {
        guard permits(request.grantRoot), let tools else { return .deny }
        let details = [request.reason ?? "Codex requested permission to modify files", request.grantRoot ?? writeWorkspace]
            .compactMap(\.self).joined(separator: "\n")
        return await tools.approve(.files(details)) ? .approve : .deny
    }

    var tools: (any AgentTools)? {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    func handle(_ call: DynamicToolCallParams) async -> DynamicToolCallResponse {
        guard let tools else {
            return AgentToolset.reply("No turn is running.", success: false)
        }
        return await AgentToolset.handle(call, tools: tools)
    }
}

/// The tools registered with Codex. `show_cards` carries ``SlackUI`` cards; the others act through
/// ``AgentTools``.
///
/// swift-codex runs a handler while it reads the app-server's messages, so a handler that waits, as
/// `ask_user` does for a click, holds every other message until it returns. Stopping a turn resolves the
/// question first so the interrupt can go through.
enum AgentToolset {
    static let setTitle = "set_title"
    static let readSlack = "read_slack"
    static let askUser = "ask_user"
    static let startCodeChannel = "start_code_channel"
    static let publishCodeView = "publish_code_view"
    static let archiveCodeChannel = "archive_code_channel"

    static let specs: [DynamicToolSpec] = [
        function(
            SlackUI.toolName,
            description: """
            Show cards under your answer in Slack, one per item worth highlighting. Each card may link to an \
            https URL and offer a follow-up question the person can ask with one click.
            """,
            properties: [
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
            required: ["cards"],
        ),
        function(
            setTitle,
            description: "Rename this Slack conversation to a short title that says what it is about, once the topic is clear.",
            properties: ["title": ["type": "string", "minLength": 1, "maxLength": 200]],
            required: ["title"],
        ),
        function(
            readSlack,
            description: """
            Read recent messages from this Slack conversation: the current thread, or the channel it is in. \
            Use it when the person refers to something said earlier.
            """,
            properties: [
                "scope": ["type": "string", "enum": ["thread", "channel"]],
                "limit": ["type": "integer", "minimum": 1, "maximum": 50],
            ],
            required: ["scope"],
        ),
        function(
            askUser,
            description: """
            Ask the person to choose between a few options and wait for their answer. Use it before acting on \
            a choice that is theirs to make, such as which approach to take.
            """,
            properties: [
                "question": ["type": "string", "minLength": 1, "maxLength": 500],
                "options": [
                    "type": "array",
                    "minItems": 2,
                    "maxItems": 5,
                    "items": ["type": "string", "minLength": 1, "maxLength": 75],
                ],
            ],
            required: ["question", "options"],
        ),
    ] + codeSpecs

    static func title(for tool: String) -> String {
        switch tool {
        case SlackUI.toolName: "Prepare cards"
        case setTitle: "Rename the conversation"
        case readSlack: "Read the conversation"
        case askUser: "Ask you a question"
        default: "Use \(tool)"
        }
    }

    /// Answers a tool call. `show_cards` only checks its arguments: the cards are read from the completed
    /// tool call item.
    static func handle(_ call: DynamicToolCallParams, tools: any AgentTools) async -> DynamicToolCallResponse {
        guard call.namespace == nil else {
            return reply("There is no tool named \(call.tool).", success: false)
        }
        do {
            let arguments = try JSONEncoder().encode(call.arguments)
            switch call.tool {
            case startCodeChannel:
                let args = try decode(StartCodeChannelArguments.self, from: arguments)
                guard !args.name.isEmpty else { throw AgentToolError(description: "Pass a channel name.") }
                let channel = try await tools.startCodeChannel(name: args.name)
                if tools.currentCodeChannel == channel {
                    return reply("You are already in <#\(channel)>. Continue the requested work here now. No task was handed off and no new channel was created.", success: true)
                }
                return reply("The task continues in <#\(channel)>. Do not perform this task again in the origin thread.", success: true)
            case publishCodeView:
                let args = try decode(CodeViewArguments.self, from: arguments)
                try await tools.publishView(args.view())
                return reply("Published the code channel view.", success: true)
            case archiveCodeChannel:
                let args = try decode(ArchiveArguments.self, from: arguments)
                guard !args.summary.isEmpty else { throw AgentToolError(description: "Pass a summary.") }
                try await tools.archiveCodeChannel(summary: args.summary)
                return reply("Posted the summary and archived the code channel.", success: true)
            case SlackUI.toolName:
                _ = try SlackUI(arguments: arguments)
                return reply("The cards will appear under your answer.", success: true)
            case setTitle:
                let title = try decode(SetTitleArguments.self, from: arguments).title
                guard !title.isEmpty else {
                    return reply("Pass a non-empty title.", success: false)
                }
                try await tools.setTitle(title)
                return reply("Renamed the conversation.", success: true)
            case readSlack:
                let read = try decode(ReadSlackArguments.self, from: arguments)
                let limit = min(max(read.limit ?? 20, 1), 50)
                return try await reply(tools.readSlack(read.scope, limit: limit), success: true)
            case askUser:
                let ask = try decode(AskUserArguments.self, from: arguments)
                guard !ask.question.isEmpty, (2 ... 5).contains(ask.options.count) else {
                    return reply("Pass a question and two to five options.", success: false)
                }
                let choice = try await tools.askUser(ask.question, options: ask.options)
                return reply("The person chose: \(choice)", success: true)
            default:
                return reply("There is no tool named \(call.tool).", success: false)
            }
        } catch let error as SlackUI.InvalidArguments {
            return reply(error.message, success: false)
        } catch let error as AgentToolError {
            return reply(error.description, success: false)
        } catch {
            return reply("The tool failed: \(error)", success: false)
        }
    }

    private struct SetTitleArguments: Decodable {
        var title: String
    }

    private struct ReadSlackArguments: Decodable {
        var scope: SlackReadScope
        var limit: Int?
    }

    private struct AskUserArguments: Decodable {
        var question: String
        var options: [String]
    }

    private static func decode<T: Decodable>(_: T.Type, from arguments: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: arguments)
        } catch {
            throw AgentToolError(description: "The arguments do not match the tool's schema.")
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

    static func reply(_ text: String, success: Bool) -> DynamicToolCallResponse {
        DynamicToolCallResponse(contentItems: [.inputText(.init(text: text, type: .inputText))], success: success)
    }

    static func function(
        _ name: String,
        description: String,
        properties: JSONObject,
        required: [String],
    ) -> DynamicToolSpec {
        .function(.init(
            description: description,
            inputSchema: [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
                "additionalProperties": false,
            ],
            name: name,
            type: .function,
        ))
    }
}
