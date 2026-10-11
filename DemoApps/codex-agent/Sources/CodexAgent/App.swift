import Configuration
import Foundation
import Logging
import SlackKit
import SlackStreaming
import SystemPackage

@main
struct CodexAgentApp {
    enum ConfigurationError: Error {
        case missingEnvironmentVariable(String)
        case unknownBackend(String)
        case unsafeWorkspace(String)
    }

    struct Environment {
        let slackToken: String
        let slackAppToken: String?
        let signingSecret: String?
        let host: String
        let port: Int
        let backend: String
        let codexPath: String?
        let codexModel: String?
        let workspace: String?
        /// The users the agent answers, or everyone when empty.
        let allowedUserIds: Set<String>
    }

    static let logger: Logger = {
        var logger = Logger(label: "codex-agent")
        logger.logLevel = .info
        return logger
    }()

    /// Prompts for a repository set with `CODEX_WORKSPACE`.
    static let workspacePrompts: [(title: String, message: String)] = [
        ("Explain this repository", "What does this repository do? Give me a short tour of its layout."),
        ("Find a function", "Where is the main entry point, and what does it do?"),
        ("Review recent changes", "Summarize the most recent commit and point out anything risky."),
    ]

    /// Prompts for the empty default workspace.
    static let generalPrompts: [(title: String, message: String)] = [
        ("Explain a concept", "Explain Swift's structured concurrency in a few short paragraphs."),
        ("Write a script", "Write a shell script that lists the ten largest files in a directory."),
        ("Debug an error", "What usually causes \"Sendable\" warnings in Swift 6, and how do I fix them?"),
    ]

    static func main() async throws {
        let environment = try await loadEnvironment()
        let backend = try makeBackend(from: environment)
        let isAllowed: @Sendable (String) -> Bool = { user in
            environment.allowedUserIds.isEmpty || environment.allowedUserIds.contains(user)
        }
        let questions = PendingQuestions()
        let responder = AgentResponder(backend: backend, questions: questions, logger: logger)
        let router = Router()

        // In the Agent messaging experience, app_home_opened with tab "messages" replaces
        // assistant_thread_started. Suggested prompts sit at the top of the Messages tab.
        router.onEvent(AppHomeOpenedEvent.self) { context, _, event in
            guard event.tab == "messages", let channel = event.channel else { return }
            let prompts = environment.workspace == nil ? generalPrompts : workspacePrompts
            try await setSuggestedPrompts(prompts, channel: channel, client: context.client)
        }

        // Direct messages to the agent, from the Messages tab or the split view, and replies in channel
        // threads the agent takes part in, so a conversation continues without mentioning it each time.
        router.onEvent(MessageEvent.self) { context, envelope, event in
            guard event.botId == nil,
                  let user = event.user,
                  let channel = event.channel,
                  let ts = event.ts,
                  let text = event.text, !text.isEmpty else {
                return
            }
            let turn = AgentResponder.Turn(
                session: SessionKey(channel: channel, threadTs: event.threadTs ?? ts),
                messageTs: ts,
                prompt: text,
                userId: user,
                teamId: envelope.teamId,
            )
            if event.channelType == "im" {
                guard isAllowed(user) else {
                    return await postNotAllowed(turn, client: context.client)
                }
                startTurn(turn, responder: responder, client: context.client)
            } else if event.threadTs != nil, isAllowed(user) {
                startTurn(turn, responder: responder, client: context.client) {
                    await responder.shouldAnswerThreadReply(text: text, in: turn.session, client: context.client)
                }
            }
        }

        // Mentions in channels; the reply goes into the mention's thread.
        router.onEvent(AppMentionEvent.self) { context, envelope, event in
            guard let user = event.user,
                  let channel = event.channel,
                  let ts = event.ts,
                  let text = event.text else {
                return
            }
            let prompt = text.replacing(/<@[A-Z0-9]+>\s*/, with: "")
            guard !prompt.isEmpty else { return }
            let turn = AgentResponder.Turn(
                session: SessionKey(channel: channel, threadTs: event.threadTs ?? ts),
                messageTs: ts,
                prompt: prompt,
                userId: user,
                teamId: envelope.teamId,
            )
            guard isAllowed(user) else {
                return await postNotAllowed(turn, client: context.client)
            }
            startTurn(turn, responder: responder, client: context.client)
        }

        // Subscribing to agent_session_stopped is what makes Slack show the stop button.
        router.onEvent(AgentSessionStoppedEvent.self) { _, _, event in
            guard let channel = event.channel, let threadTs = event.threadTs else { return }
            await responder.stop(SessionKey(channel: channel, threadTs: threadTs))
        }

        router.onEvent(AgentSessionTitleChangedEvent.self) { _, _, event in
            guard let channel = event.channel, let threadTs = event.threadTs else { return }
            logger.info("Session renamed", metadata: ["title": "\(event.title ?? "")"])
            await responder.titleChanged(SessionKey(channel: channel, threadTs: threadTs))
        }

        Feedback.register(on: router, logger: logger)

        // Answers to the agent's ask_user tool, one action_id per option. Only the person asked can answer.
        for index in 0 ..< SlackAgentTools.maxOptions {
            let actionId = SlackAgentTools.choiceActionId(index)
            router.onAction(actionId) { context, payload in
                try await context.ack()
                guard let id = payload.blockActions.first(where: { $0.actionId == actionId })?.value,
                      let user = payload.user.id, let channel = payload.container.channelId else {
                    return
                }
                let notice: String? = switch await questions.answer(id: id, index: index, userId: user) {
                case .accepted: nil
                case let .notAsked(asked): "Only <@\(asked)> can answer this question."
                case .expired: "This question is no longer waiting for an answer."
                }
                if let notice {
                    _ = try await context.client.chatPostEphemeral(body: .json(.init(
                        channel: channel,
                        text: notice,
                        threadTs: payload.message?.threadTs ?? payload.container.messageTs,
                        user: user,
                    ))).ok.body.json.checked("chat.postEphemeral")
                }
            }
        }

        // Buttons on the cards from the agent's show_cards tool.
        router.onAction(SlackUI.openActionId) { context, _ in
            // Slack opens the link; the click still needs an acknowledgement.
            try await context.ack()
        }
        router.onAction(SlackUI.askActionId) { context, payload in
            try await context.ack()
            guard let question = payload.blockActions.first(where: { $0.actionId == SlackUI.askActionId })?.value,
                  let channel = payload.container.channelId,
                  let messageTs = payload.container.messageTs,
                  let user = payload.user.id, isAllowed(user),
                  let teamId = payload.team.id else {
                return
            }
            // Post the question so the thread shows what the agent is answering.
            let threadTs = payload.message?.threadTs ?? messageTs
            let posted = try await context.client.chatPostMessage(body: .json(.init(
                channel: channel,
                text: "<@\(user)> asked: \(question)",
                threadTs: threadTs,
            ))).ok.body.json.checked("chat.postMessage")
            let turn = AgentResponder.Turn(
                session: SessionKey(channel: channel, threadTs: threadTs),
                messageTs: posted.ts ?? messageTs,
                prompt: question,
                userId: user,
                teamId: teamId,
            )
            startTurn(turn, responder: responder, client: context.client)
        }

        let app = try SlackApp(
            configuration: configuration(from: environment),
            router: router,
            mode: runtimeMode(from: environment),
        )
        logger.info("Codex agent is running", metadata: ["backend": "\(environment.backend)"])
        try await app.run { slack in
            let response = try await slack.client.authTest().ok.body.json.checked("auth.test")
            guard let userId = response.userId else {
                throw SlackAPIError(method: "auth.test", code: "missing_user_id")
            }
            await responder.setIdentity(BotIdentity(userId: userId, botId: response.botId))
        }
    }

    /// Runs the turn outside the event handler: in HTTP mode, swift-slack answers the event request only
    /// after the handler returns, and Slack retries events that take longer than three seconds.
    private static func startTurn(
        _ turn: AgentResponder.Turn,
        responder: AgentResponder,
        client: any APIProtocol,
        if shouldStart: @escaping @Sendable () async -> Bool = { true },
    ) {
        Task {
            guard await shouldStart() else { return }
            await responder.handle(turn, client: client)
        }
    }

    private static func postNotAllowed(_ turn: AgentResponder.Turn, client: any APIProtocol) async {
        logger.info("Ignoring a message from a user not in ALLOWED_USER_IDS", metadata: ["user": "\(turn.userId)"])
        do {
            _ = try await client.chatPostEphemeral(body: .json(.init(
                channel: turn.session.channel,
                text: "Sorry, this agent only answers the people it is set up for.",
                threadTs: turn.session.threadTs,
                user: turn.userId,
            ))).ok.body.json.checked("chat.postEphemeral")
        } catch {
            logger.warning("Failed to post the not-allowed notice", metadata: ["error": "\(error)"])
        }
    }

    private static func setSuggestedPrompts(
        _ prompts: [(title: String, message: String)],
        channel: String,
        client: any APIProtocol,
    ) async throws {
        // swift-slack types `prompts` as a string because slack-api-ref does; requests are form-encoded,
        // so it takes the JSON array as text.
        let objects = prompts.map { ["title": $0.title, "message": $0.message] }
        let json = try String(decoding: JSONSerialization.data(withJSONObject: objects), as: UTF8.self)
        _ = try await client.assistantThreadsSetSuggestedPrompts(body: .json(.init(
            channelId: channel,
            prompts: json,
            title: "What can I help with?",
        ))).ok.body.json.checked("assistant.threads.setSuggestedPrompts")
    }

    private static func makeBackend(from environment: Environment) throws -> any AgentBackend {
        switch environment.backend {
        case "codex":
            // Codex can read the whole disk, even in its read-only sandbox, and its answers go to Slack.
            // Keep the app's own secrets out of its working directory, and warn when anyone can ask.
            if environment.allowedUserIds.isEmpty {
                logger.warning("ALLOWED_USER_IDS is not set: anyone who can message the app can make Codex read files")
            }
            return try CodexBackend(
                settings: .init(
                    codexPath: environment.codexPath,
                    model: environment.codexModel,
                    workspace: environment.workspace.map(checkedWorkspace) ?? emptyWorkspace(),
                ),
                logger: logger,
            )
        case "mock":
            return MockBackend()
        default:
            throw ConfigurationError.unknownBackend(environment.backend)
        }
    }

    /// An empty directory for Codex to work in when `CODEX_WORKSPACE` is not set. The app's own directory
    /// would expose `.env`, which holds the Slack tokens.
    private static func emptyWorkspace() throws -> String {
        let directory = FileManager.default.temporaryDirectory.appending(path: "codex-agent-workspace")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logger.info("CODEX_WORKSPACE is not set; Codex works in an empty directory", metadata: [
            "path": "\(directory.path(percentEncoded: false))",
        ])
        return directory.path(percentEncoded: false)
    }

    /// Rejects a workspace that contains the app's directory, where `.env` holds the Slack tokens, or that
    /// has a `.env` of its own.
    private static func checkedWorkspace(_ path: String) throws -> String {
        let workspace = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        let appDirectory = URL(filePath: FileManager.default.currentDirectoryPath)
            .standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = workspace.path(percentEncoded: false)
        let appPath = appDirectory.path(percentEncoded: false)
        let containsApp = appPath == workspacePath
            || appPath.hasPrefix(workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/")
        if containsApp {
            throw ConfigurationError.unsafeWorkspace("CODEX_WORKSPACE contains the app's directory and its .env")
        }
        if FileManager.default.fileExists(atPath: workspace.appending(path: ".env").path(percentEncoded: false)) {
            throw ConfigurationError.unsafeWorkspace("CODEX_WORKSPACE has a .env file")
        }
        return workspacePath
    }

    private static func loadEnvironment() async throws -> Environment {
        let envFilePath = FileManager.default.currentDirectoryPath + "/.env"
        let secrets: Set = ["SLACK_BOT_TOKEN", "SLACK_APP_TOKEN", "SLACK_SIGNING_SECRET"]
        let fileProvider = try await EnvironmentVariablesProvider(
            environmentFilePath: FilePath(envFilePath),
            allowMissing: true,
            secretsSpecifier: .specific(secrets),
        )
        let configuration = ConfigReader(providers: [
            EnvironmentVariablesProvider(secretsSpecifier: .specific(secrets)),
            fileProvider,
        ])

        return try Environment(
            slackToken: requiredString("SLACK_BOT_TOKEN", in: configuration),
            slackAppToken: normalized(configuration.string(forKey: "SLACK_APP_TOKEN", isSecret: true)),
            signingSecret: normalized(configuration.string(forKey: "SLACK_SIGNING_SECRET", isSecret: true)),
            host: normalized(configuration.string(forKey: "HOST")) ?? "0.0.0.0",
            port: configuration.int(forKey: "PORT", default: 8080),
            backend: normalized(configuration.string(forKey: "AGENT_BACKEND")) ?? "codex",
            codexPath: normalized(configuration.string(forKey: "CODEX_PATH")),
            codexModel: normalized(configuration.string(forKey: "CODEX_MODEL")),
            workspace: normalized(configuration.string(forKey: "CODEX_WORKSPACE")),
            allowedUserIds: Set(
                (configuration.string(forKey: "ALLOWED_USER_IDS") ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
            ),
        )
    }

    private static func requiredString(_ key: String, in configuration: ConfigReader) throws -> String {
        guard let value = normalized(configuration.string(forKey: ConfigKey(key), isSecret: true)) else {
            throw ConfigurationError.missingEnvironmentVariable(key)
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func configuration(from environment: Environment) throws -> SlackApp.Configuration {
        #if HummingbirdHTTPAdapter
        guard let signingSecret = environment.signingSecret else {
            throw ConfigurationError.missingEnvironmentVariable("SLACK_SIGNING_SECRET")
        }
        return .init(userAgent: "CodexAgent/1.0", token: environment.slackToken, signingSecret: signingSecret)
        #else
        guard let appToken = environment.slackAppToken else {
            throw ConfigurationError.missingEnvironmentVariable("SLACK_APP_TOKEN")
        }
        return .init(userAgent: "CodexAgent/1.0", appToken: appToken, token: environment.slackToken)
        #endif
    }

    private static func runtimeMode(from environment: Environment) -> SlackApp.Mode {
        #if HummingbirdHTTPAdapter
        return .http(HummingbirdAdapter(hostname: environment.host, port: environment.port))
        #else
        return .socketMode()
        #endif
    }
}
