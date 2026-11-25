import Configuration
import Foundation
import Logging
import SlackKit
import SystemPackage

/// Startup settings and workspace validation.
struct AgentConfiguration {
    enum Error: Swift.Error {
        case missingEnvironmentVariable(String)
        case unsafeWorkspace(String)
    }

    let slack: SlackApp.Configuration
    let host: String
    let port: Int
    let codexPath: String?
    let codexModel: String?
    let workspace: String?
    let sessionWorkspaces: String?
    /// The users the agent answers, or everyone when empty.
    let allowedUserIds: Set<String>

    static func makeCodex(from environment: Self, logger: Logger) throws -> CodexRuntime {
        if environment.sessionWorkspaces != nil, environment.workspace == nil {
            throw Error.missingEnvironmentVariable("CODEX_WORKSPACE")
        }
        // Codex can read the whole disk, even in its read-only sandbox, and its answers go to Slack.
        // Keep the app's own secrets out of its working directory, and warn when anyone can ask.
        if environment.allowedUserIds.isEmpty {
            logger.warning("ALLOWED_USER_IDS is not set: anyone who can message the app can make Codex read files")
        }
        return try CodexRuntime(
            settings: .init(
                codexPath: environment.codexPath,
                model: environment.codexModel,
                workspace: environment.workspace.map { try checkedWorkspace($0) } ?? emptyWorkspace(logger: logger),
                sessionWorkspaces: environment.sessionWorkspaces,
            ),
            logger: logger,
        )
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
        // The Slack keys are read as secrets by `SlackApp.Configuration(config:)`.
        let fileProvider = try await EnvironmentVariablesProvider(
            environmentFilePath: FilePath(envFilePath),
            allowMissing: true,
        )
        let reader = ConfigReader(providers: [
            EnvironmentVariablesProvider(),
            fileProvider,
        ])

        let slack = SlackApp.Configuration(config: reader, userAgent: "CodexAgent/1.0")
        guard slack.token != nil else {
            throw Error.missingEnvironmentVariable("SLACK_BOT_TOKEN")
        }

        return Self(
            slack: slack,
            host: normalized(reader.string(forKey: "HOST")) ?? "0.0.0.0",
            port: reader.int(forKey: "PORT", default: 8080),
            codexPath: normalized(reader.string(forKey: "CODEX_PATH")),
            codexModel: normalized(reader.string(forKey: "CODEX_MODEL")),
            workspace: normalized(reader.string(forKey: "CODEX_WORKSPACE")),
            sessionWorkspaces: normalized(reader.string(forKey: "CODEX_SESSION_WORKSPACES")),
            allowedUserIds: Set(
                (reader.string(forKey: "ALLOWED_USER_IDS") ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
            ),
        )
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func configuration(from environment: Self) throws -> SlackApp.Configuration {
        #if HummingbirdHTTPAdapter
        guard environment.slack.signingSecret != nil else {
            throw Error.missingEnvironmentVariable("SLACK_SIGNING_SECRET")
        }
        #else
        guard environment.slack.appToken != nil else {
            throw Error.missingEnvironmentVariable("SLACK_APP_TOKEN")
        }
        #endif
        return environment.slack
    }

    static func runtimeMode(from environment: Self) -> SlackApp.Mode {
        #if HummingbirdHTTPAdapter
        return .http(HummingbirdAdapter(hostname: environment.host, port: environment.port))
        #else
        return .socketMode()
        #endif
    }
}
