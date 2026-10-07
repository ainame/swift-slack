import Foundation
import SlackBlockKitDSL
import SlackKit

/// Serves external select menus over Socket Mode.
///
/// `/pick` opens a modal with two external select menus. As you type, Slack sends `block_suggestion` requests:
/// the fruit menu is answered with options, and the city menu with option groups.
///
/// Slack app setup: enable Socket Mode and Interactivity, and create the `/pick` slash command.
/// External select menus in Socket Mode apps need no options load URL.
@main
struct ExternalSelectCommand {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["SLACK_OAUTH_TOKEN"],
              let appToken = ProcessInfo.processInfo.environment["SLACK_APP_LEVEL_TOKEN"] else {
            print("❌ Please set SLACK_OAUTH_TOKEN and SLACK_APP_LEVEL_TOKEN environment variables")
            print("   SLACK_OAUTH_TOKEN: Bot token (starts with xoxb-)")
            print("   SLACK_APP_LEVEL_TOKEN: App-level token (starts with xapp-)")
            exit(1)
        }

        let router = Router()

        router.onSlashCommand("/pick") { context, payload in
            try await context.ack()

            let view = Modal(title: Text("Pick favorites")) {
                Input("Fruit") {
                    ExternalSelect()
                        .actionId("fruit")
                        .placeholder("Type a fruit")
                        .minQueryLength(0)
                }
                .blockId("fruit_block")

                Input("City") {
                    ExternalSelect()
                        .actionId("city")
                        .placeholder("Type a city")
                        .minQueryLength(1)
                }
                .blockId("city_block")
            }
            .submit(Text("Save"))
            .callbackId("pick_favorites")
            .asView()

            _ = try await context.client.viewsOpen(
                .init(body: .json(.init(triggerId: payload.triggerId, view: view))),
            )
        }

        // Respond with a flat list of options.
        router.onBlockSuggestion("fruit") { context, payload in
            let matches = fruits.filter { isMatch($0, query: payload.value) }
            try await context.ack(options: matches.prefix(100).map { Option($0).value($0.lowercased()).render() })
        }

        // Respond with options grouped by region. Empty groups are left out.
        router.onBlockSuggestion("city", blockId: "city_block") { context, payload in
            let groups = citiesByRegion.compactMap { region, cities -> OptionGroupObject? in
                let matches = cities.filter { isMatch($0, query: payload.value) }
                guard !matches.isEmpty else { return nil }
                return OptionGroup(label: region) {
                    for city in matches {
                        Option(city).value(city.lowercased())
                    }
                }
                .render()
            }
            try await context.ack(optionGroups: Array(groups.prefix(100)))
        }

        router.onViewSubmission("pick_favorites") { context, payload in
            try await context.ack()

            let state = payload.view.state
            let fruit = state?["fruit_block", "fruit"]?.selectedOption?.text.text ?? "nothing"
            let city = state?["city_block", "city"]?.selectedOption?.text.text ?? "nowhere"
            context.logger.info("\(payload.user.id) picked \(fruit) in \(city)")
        }

        let app = SlackApp(
            configuration: .init(
                userAgent: "ExternalSelect/1.0",
                appToken: appToken,
                token: token,
            ),
            router: router,
            mode: .socketMode(),
        )

        print("🚀 Starting external select demo. Run /pick in Slack.")
        try await app.run()
    }
}

private let fruits = [
    "Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Grape", "Kiwi", "Lemon", "Mango", "Orange", "Peach",
    "Pear", "Pineapple", "Plum", "Strawberry", "Watermelon",
]

private let citiesByRegion: KeyValuePairs<String, [String]> = [
    "Asia": ["Bangkok", "Seoul", "Singapore", "Tokyo"],
    "Europe": ["Berlin", "London", "Madrid", "Paris"],
    "North America": ["Chicago", "Mexico City", "New York", "Toronto"],
]

private func isMatch(_ name: String, query: String) -> Bool {
    query.isEmpty || name.localizedCaseInsensitiveContains(query)
}
