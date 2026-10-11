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
        let workspace: String
    }

    static let logger: Logger = {
        var logger = Logger(label: "codex-agent")
        logger.logLevel = .info
        return logger
    }()

    static let suggestedPrompts: [(title: String, message: String)] = [
        ("Explain this repository", "What does this repository do? Give me a short tour of its layout."),
        ("Find a function", "Where is the main entry point, and what does it do?"),
        ("Review recent changes", "Summarize the most recent commit and point out anything risky."),
    ]

    static func main() async throws {
        let environment = try await loadEnvironment()
        let backend = try makeBackend(from: environment)
        let responder = AgentResponder(backend: backend, logger: logger)
        let router = Router()

        // In the Agent messaging experience, app_home_opened with tab "messages" replaces
        // assistant_thread_started. Suggested prompts sit at the top of the Messages tab.
        router.onEvent(AppHomeOpenedEvent.self) { context, _, event in
            guard event.tab == "messages", let channel = event.channel else { return }
            try await setSuggestedPrompts(channel: channel, client: context.client)
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
                startTurn(turn, responder: responder, client: context.client)
            } else if event.threadTs != nil {
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

    private static func setSuggestedPrompts(channel: String, client: any APIProtocol) async throws {
        // swift-slack types `prompts` as a string because slack-api-ref does; requests are form-encoded,
        // so it takes the JSON array as text.
        let prompts = suggestedPrompts.map { ["title": $0.title, "message": $0.message] }
        let json = try String(decoding: JSONSerialization.data(withJSONObject: prompts), as: UTF8.self)
        _ = try await client.assistantThreadsSetSuggestedPrompts(body: .json(.init(
            channelId: channel,
            prompts: json,
            title: "Ask Codex about the workspace",
        ))).ok.body.json.checked("assistant.threads.setSuggestedPrompts")
    }

    private static func makeBackend(from environment: Environment) throws -> any AgentBackend {
        switch environment.backend {
        case "codex":
            CodexBackend(
                settings: .init(
                    codexPath: environment.codexPath,
                    model: environment.codexModel,
                    workspace: environment.workspace,
                ),
                logger: logger,
            )
        case "mock":
            MockBackend()
        default:
            throw ConfigurationError.unknownBackend(environment.backend)
        }
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
            workspace: normalized(configuration.string(forKey: "CODEX_WORKSPACE"))
                ?? FileManager.default.currentDirectoryPath,
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
