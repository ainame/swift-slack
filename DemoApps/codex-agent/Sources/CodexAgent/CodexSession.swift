import Codex
import Foundation
import Logging

actor CodexSession {
    private let settings: CodexRuntime.Settings
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
        settings: CodexRuntime.Settings,
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
        tools: SlackAgentTools,
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
        tools: SlackAgentTools,
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
