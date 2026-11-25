#if SwiftConfiguration
import Configuration
#endif
import Foundation

extension Slack {
    public struct Configuration: Sendable {
        public var userAgent: String?
        public var appToken: String?
        public var token: String?
        public var signingSecret: String?

        public init(
            userAgent: String? = nil,
            appToken: String? = nil,
            token: String? = nil,
            signingSecret: String? = nil,
        ) {
            self.userAgent = userAgent
            self.appToken = appToken
            self.token = token
            self.signingSecret = signingSecret
        }
    }
}

extension Slack.Configuration {
    /// Creates a configuration from the conventional Slack environment variables.
    ///
    /// Reads the bot token from `SLACK_BOT_TOKEN`, the app-level token from `SLACK_APP_TOKEN`,
    /// and the signing secret from `SLACK_SIGNING_SECRET`. A variable that is unset, empty,
    /// or only whitespace leaves its property `nil`; surrounding whitespace is trimmed.
    ///
    /// Bolt apps read the same variables. For `slack run`, the Slack CLI sets `SLACK_BOT_TOKEN`
    /// and `SLACK_APP_TOKEN` to the development app's tokens when they are not already set; it
    /// does not set `SLACK_SIGNING_SECRET`.
    ///
    /// - Parameter userAgent: The user agent to send with Web API requests.
    public static func fromEnvironment(userAgent: String? = nil) -> Slack.Configuration {
        fromEnvironment(userAgent: userAgent, environment: ProcessInfo.processInfo.environment)
    }

    static func fromEnvironment(userAgent: String?, environment: [String: String]) -> Slack.Configuration {
        func value(_ name: String) -> String? {
            guard let trimmed = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        return .init(
            userAgent: userAgent,
            appToken: value("SLACK_APP_TOKEN"),
            token: value("SLACK_BOT_TOKEN"),
            signingSecret: value("SLACK_SIGNING_SECRET"),
        )
    }
}

#if SwiftConfiguration
extension Slack.Configuration {
    /// Creates a configuration from a swift-configuration reader.
    ///
    /// Reads these keys as secrets. Each is optional, and an empty or whitespace-only value
    /// leaves its property `nil`:
    ///
    /// | Key | Property | Environment variable |
    /// | --- | --- | --- |
    /// | `slack.botToken` | ``token`` | `SLACK_BOT_TOKEN` |
    /// | `slack.appToken` | ``appToken`` | `SLACK_APP_TOKEN` |
    /// | `slack.signingSecret` | ``signingSecret`` | `SLACK_SIGNING_SECRET` |
    ///
    /// Through `EnvironmentVariablesProvider`, the keys read the same variables as
    /// ``fromEnvironment(userAgent:)``, including the tokens the Slack CLI sets for `slack run`.
    /// Other providers, such as a JSON file, nest the keys under `slack`.
    ///
    /// Requires the `SwiftConfiguration` package trait.
    ///
    /// - Parameters:
    ///   - config: The reader to read the Slack keys from.
    ///   - userAgent: The user agent to send with Web API requests.
    public init(config: ConfigReader, userAgent: String? = nil) {
        let slack = config.scoped(to: "slack")
        func value(_ key: ConfigKey) -> String? {
            guard let trimmed = slack.string(forKey: key, isSecret: true)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        self.init(
            userAgent: userAgent,
            appToken: value("appToken"),
            token: value("botToken"),
            signingSecret: value("signingSecret"),
        )
    }
}
#endif
