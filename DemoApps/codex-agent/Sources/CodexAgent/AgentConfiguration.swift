import Configuration
import Foundation
import Logging
import SlackKit
import SystemPackage

/// Startup settings, backend selection and workspace validation.
struct AgentConfiguration {
    enum Error: Swift.Error {
        case missingEnvironmentVariable(String)
        case unknownBackend(String)
        case unsafeWorkspace(String)
    }

    let slackToken: String
    let slackAppToken: String?
    let signingSecret: String?
    let host: String
    let port: Int
    let backend: String
    let codexPath: String?
    let codexModel: String?
    let workspace: String?
    let sessionWorkspaces: String?
    /// The users the agent answers, or everyone when empty.
    let allowedUserIds: Set<String>

    static func makeBackend(from environment: Self, logger: Logger) throws -> any AgentBackend {
        switch environment.backend {
        case "codex":
            if environment.sessionWorkspaces != nil, environment.workspace == nil {
                throw Error.missingEnvironmentVariable("CODEX_WORKSPACE")
            }
            // Codex can read the whole disk, even in its read-only sandbox, and its answers go to Slack.
            // Keep the app's own secrets out of its working directory, and warn when anyone can ask.
            if environment.allowedUserIds.isEmpty {
                logger.warning("ALLOWED_USER_IDS is not set: anyone who can message the app can make Codex read files")
            }
            return try CodexBackend(
                settings: .init(
                    codexPath: environment.codexPath,
                    model: environment.codexModel,
                    workspace: environment.workspace.map { try checkedWorkspace($0) } ?? emptyWorkspace(logger: logger),
                    sessionWorkspaces: environment.sessionWorkspaces,
                ),
                logger: logger,
            )
        case "mock":
            return MockBackend()
        default:
            throw Error.unknownBackend(environment.backend)
        }
    }

    /// An empty directory for Codex to work in when `CODEX_WORKSPACE` is not set. The app's own directory
    /// would expose `.env`, which holds the Slack tokens.
    private static func emptyWorkspace(logger: Logger) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appending(path: "codex-agent-workspace")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logger.info("CODEX_WORKSPACE is not set; Codex works in an empty directory", metadata: [
            "path": "\(directory.path(percentEncoded: false))",
        ])
        return directory.path(percentEncoded: false)
    }

    /// Rejects a workspace that contains the app's `.env` file or has a `.env` of its own.
    static func checkedWorkspace(
        _ path: String,
        appDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath),
    ) throws -> String {
        let workspace = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        let appDirectory = appDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = workspace.path(percentEncoded: false)
        let appPath = appDirectory.path(percentEncoded: false)
        let containsApp = appPath == workspacePath
            || appPath.hasPrefix(workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/")
        if containsApp,
           FileManager.default.fileExists(atPath: appDirectory.appending(path: ".env").path(percentEncoded: false)) {
            throw Error.unsafeWorkspace("CODEX_WORKSPACE contains the app's directory and its .env")
        }
        if FileManager.default.fileExists(atPath: workspace.appending(path: ".env").path(percentEncoded: false)) {
            throw Error.unsafeWorkspace("CODEX_WORKSPACE has a .env file")
        }
        return workspacePath
    }

    static func load() async throws -> Self {
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

        return try Self(
            slackToken: requiredString("SLACK_BOT_TOKEN", in: configuration),
            slackAppToken: normalized(configuration.string(forKey: "SLACK_APP_TOKEN", isSecret: true)),
            signingSecret: normalized(configuration.string(forKey: "SLACK_SIGNING_SECRET", isSecret: true)),
            host: normalized(configuration.string(forKey: "HOST")) ?? "0.0.0.0",
            port: configuration.int(forKey: "PORT", default: 8080),
            backend: normalized(configuration.string(forKey: "AGENT_BACKEND")) ?? "codex",
            codexPath: normalized(configuration.string(forKey: "CODEX_PATH")),
            codexModel: normalized(configuration.string(forKey: "CODEX_MODEL")),
            workspace: normalized(configuration.string(forKey: "CODEX_WORKSPACE")),
            sessionWorkspaces: normalized(configuration.string(forKey: "CODEX_SESSION_WORKSPACES")),
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
            throw Error.missingEnvironmentVariable(key)
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func configuration(from environment: Self) throws -> SlackApp.Configuration {
        #if HummingbirdHTTPAdapter
        guard let signingSecret = environment.signingSecret else {
            throw Error.missingEnvironmentVariable("SLACK_SIGNING_SECRET")
        }
        return .init(userAgent: "CodexAgent/1.0", token: environment.slackToken, signingSecret: signingSecret)
        #else
        guard let appToken = environment.slackAppToken else {
            throw Error.missingEnvironmentVariable("SLACK_APP_TOKEN")
        }
        return .init(userAgent: "CodexAgent/1.0", appToken: appToken, token: environment.slackToken)
        #endif
    }

    static func runtimeMode(from environment: Self) -> SlackApp.Mode {
        #if HummingbirdHTTPAdapter
        return .http(HummingbirdAdapter(hostname: environment.host, port: environment.port))
        #else
        return .socketMode()
        #endif
    }
}
