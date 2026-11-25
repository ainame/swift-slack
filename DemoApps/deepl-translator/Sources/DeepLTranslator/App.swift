import AsyncHTTPClient
import Configuration
import Foundation
import Logging
import SlackKit
import SystemPackage

@main
struct DeepLTranslatorApp {
    enum ConfigurationError: Error {
        case missingEnvironmentVariable(String)
    }

    struct Environment {
        let slack: SlackApp.Configuration
        let deepLAPIKey: String
        let isFreePlan: Bool
        let runnerLanguages: [String]
        let defaultLanguage: String
        let host: String
        let port: Int
    }

    static let logger: Logger = {
        var logger = Logger(label: "deepl-translator")
        logger.logLevel = .info
        return logger
    }()

    static func main() async throws {
        logger.info("Starting DeepL Translator bot...")
        let environment = try await loadEnvironment()

        logger.info("Using DeepL \(environment.isFreePlan ? "Free" : "Pro") plan")

        // Initialize shared HTTP client
        let httpClient = HTTPClient()

        let deepL = DeepLClient(
            httpClient: httpClient,
            authKey: environment.deepLAPIKey,
            isFreePlan: environment.isFreePlan,
        )
        let reactionHandler = ReactionHandler(deepL: deepL)

        // Create router
        let router = Router()

        // Handle global shortcut
        router.onGlobalShortcut("deepl-translation") { context, payload in
            try await context.ack()
            let modal = TranslationModal.buildNewModal(
                defaultLang: environment.defaultLanguage,
                languages: environment.runnerLanguages,
            )
            _ = try await context.client.viewsOpen(
                body: .json(.init(
                    triggerId: payload.triggerId,
                    view: modal,
                )),
            )
        }

        // Handle message shortcut without opening extra UI
        router.onMessageShortcut("deepl-translate-message") { context, payload in
            try await context.ack()

            guard let channelId = payload.channel.id,
                  let messageTs = payload.message.ts,
                  let text = payload.message.text,
                  !text.isEmpty else {
                logger.warning("Ignoring message shortcut without translatable text")
                return
            }

            do {
                try await postTranslatedReply(
                    client: context.client,
                    deepL: deepL,
                    channelId: channelId,
                    threadTs: payload.message.threadTs ?? messageTs,
                    text: text,
                    language: environment.defaultLanguage,
                )
            } catch {
                logger.error(
                    "Failed to post translated reply for message shortcut",
                    metadata: [
                        "channel": "\(channelId)",
                        "threadTs": "\(payload.message.threadTs ?? messageTs)",
                        "error": "\(error)",
                    ],
                )
            }
        }

        // Handle view submissions
        router.onViewSubmission("run-translation") { context, payload in
            guard let state = payload.view.state,
                  let textValue = state["text", "a"]?.value,
                  let langValue = state["lang", "a"]?.selectedOption?.value else {
                try await context.ack()
                return
            }

            let loadingView = TranslationModal.buildLoadingView()
            try await context.ack(responseAction: .update, view: loadingView)

            guard let translatedText = try await deepL.translate(text: textValue, targetLanguage: langValue) else {
                return
            }

            let resultView = TranslationModal.buildResultView(
                lang: langValue,
                originalText: textValue,
                translatedText: translatedText,
            )

            _ = try await context.client.viewsUpdate(
                body: .json(.init(
                    viewId: payload.view.id,
                    view: resultView,
                )),
            )
        }

        // Handle reaction events
        router.onEvent(ReactionAddedEvent.self) { context, _, event in
            try await reactionHandler.handleReactionAdded(
                client: context.client,
                event: event,
            )
        }

        logger.info("DeepL Translator bot is running!")

        let app = try SlackApp(
            configuration: configuration(from: environment),
            router: router,
            mode: runtimeMode(from: environment),
        )

        do {
            try await app.run()
        } catch {
            logger.critical("App runtime failed", metadata: ["error": "\(error)"])
            try await httpClient.shutdown()
            throw error
        }

        // Clean up HTTP client on normal exit
        try await httpClient.shutdown()
    }

    private static func loadEnvironment() async throws -> Environment {
        let envFilePath = FileManager.default.currentDirectoryPath + "/.env"

        if FileManager.default.fileExists(atPath: envFilePath) {
            logger.info("Loaded .env file")
        } else {
            logger.info("No .env file found, using environment variables")
        }

        // The Slack keys are read as secrets by `SlackApp.Configuration(config:)`.
        let secrets: Set<String> = ["DEEPL_API_KEY"]

        let fileProvider = try await EnvironmentVariablesProvider(
            environmentFilePath: FilePath(envFilePath),
            allowMissing: true,
            secretsSpecifier: .specific(secrets),
        )
        let reader = ConfigReader(
            providers: [
                EnvironmentVariablesProvider(secretsSpecifier: .specific(secrets)),
                fileProvider,
            ],
        )

        let runnerLanguages = Languages.getOrderedLanguages(
            from: normalized(reader.string(forKey: "DEEPL_RUNNER_LANGUAGES")),
        )

        // `slack run` provides the development app's tokens as SLACK_BOT_TOKEN and SLACK_APP_TOKEN.
        let slack = SlackApp.Configuration(config: reader, userAgent: "DeepLTranslator/1.0")
        guard slack.token != nil else {
            throw ConfigurationError.missingEnvironmentVariable("SLACK_BOT_TOKEN")
        }

        return try Environment(
            slack: slack,
            deepLAPIKey: requiredString("DEEPL_API_KEY", in: reader, isSecret: true),
            isFreePlan: reader.bool(forKey: "DEEPL_FREE_API_PLAN", default: false),
            runnerLanguages: runnerLanguages,
            defaultLanguage: runnerLanguages.first ?? "en",
            host: normalized(reader.string(forKey: "HOST", default: "0.0.0.0")) ?? "0.0.0.0",
            port: reader.int(forKey: "PORT", default: 8080),
        )
    }

    private static func requiredString(_ key: String, in reader: ConfigReader, isSecret: Bool) throws -> String {
        guard let value = normalized(reader.string(forKey: ConfigKey(key), isSecret: isSecret)) else {
            throw ConfigurationError.missingEnvironmentVariable(key)
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func configuration(from environment: Environment) throws -> SlackApp.Configuration {
        #if HummingbirdHTTPAdapter
        guard environment.slack.signingSecret != nil else {
            logger.error("SLACK_SIGNING_SECRET is required when HummingbirdHTTPAdapter trait is enabled")
            throw ConfigurationError.missingEnvironmentVariable("SLACK_SIGNING_SECRET")
        }
        logger.info("Using Hummingbird HTTP adapter")
        #else
        guard environment.slack.appToken != nil else {
            logger.error("SLACK_APP_TOKEN is required when running in Socket Mode")
            throw ConfigurationError.missingEnvironmentVariable("SLACK_APP_TOKEN")
        }
        logger.info("Using Socket Mode")
        #endif
        return environment.slack
    }

    private static func runtimeMode(from environment: Environment) -> SlackApp.Mode {
        #if HummingbirdHTTPAdapter
        return .http(HummingbirdAdapter(hostname: environment.host, port: environment.port))
        #else
        return .socketMode()
        #endif
    }

    private static func postTranslatedReply(
        client: any APIProtocol,
        deepL: DeepLClient,
        channelId: String,
        threadTs: String,
        text: String,
        language: String,
    ) async throws {
        guard let translatedText = try await deepL.translate(text: text, targetLanguage: language) else {
            logger.error("Translation failed - DeepL returned nil")
            return
        }

        _ = try await client.chatPostMessage(
            body: .json(.init(
                channel: channelId,
                text: translatedText,
                threadTs: threadTs,
            )),
        )
    }
}
