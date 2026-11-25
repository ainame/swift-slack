#if SwiftConfiguration
import Configuration
#endif
@testable import SlackClient
import Testing

struct ConfigurationEnvironmentTests {
    @Test func `reads conventional variables`() {
        let configuration = Slack.Configuration.fromEnvironment(userAgent: "Test/1.0", environment: [
            "SLACK_BOT_TOKEN": "xoxb-bot",
            "SLACK_APP_TOKEN": "xapp-app",
            "SLACK_SIGNING_SECRET": "secret",
        ])

        #expect(configuration.userAgent == "Test/1.0")
        #expect(configuration.token == "xoxb-bot")
        #expect(configuration.appToken == "xapp-app")
        #expect(configuration.signingSecret == "secret")
    }

    @Test func `leaves missing and blank variables nil`() {
        let configuration = Slack.Configuration.fromEnvironment(userAgent: nil, environment: [
            "SLACK_BOT_TOKEN": "  xoxb-bot\n",
            "SLACK_APP_TOKEN": "",
            "SLACK_SIGNING_SECRET": "   ",
        ])

        #expect(configuration.userAgent == nil)
        #expect(configuration.token == "xoxb-bot")
        #expect(configuration.appToken == nil)
        #expect(configuration.signingSecret == nil)
    }

    @Test func `ignores slack CLI variables`() {
        let configuration = Slack.Configuration.fromEnvironment(userAgent: nil, environment: [
            "SLACK_CLI_XOXB": "xoxb-cli",
            "SLACK_CLI_XAPP": "xapp-cli",
        ])

        #expect(configuration.token == nil)
        #expect(configuration.appToken == nil)
    }

    #if SwiftConfiguration
    @Test func `reader reads the conventional environment variables`() {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider(environmentVariables: [
            "SLACK_BOT_TOKEN": "xoxb-bot",
            "SLACK_APP_TOKEN": " xapp-app ",
            "SLACK_SIGNING_SECRET": "",
        ]))

        let configuration = Slack.Configuration(config: reader, userAgent: "Test/1.0")

        #expect(configuration.userAgent == "Test/1.0")
        #expect(configuration.token == "xoxb-bot")
        #expect(configuration.appToken == "xapp-app")
        #expect(configuration.signingSecret == nil)
    }

    @Test func `reader reads keys nested under slack`() {
        let reader = ConfigReader(provider: InMemoryProvider(values: [
            "slack.botToken": "xoxb-bot",
            "slack.appToken": "xapp-app",
            "slack.signingSecret": "secret",
        ]))

        let configuration = Slack.Configuration(config: reader)

        #expect(configuration.token == "xoxb-bot")
        #expect(configuration.appToken == "xapp-app")
        #expect(configuration.signingSecret == "secret")
    }
    #endif
}
