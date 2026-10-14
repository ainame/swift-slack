import Foundation
import SlackKit

/// Cards an agent asks for with the `show_cards` tool: a small vocabulary that the app turns into Block Kit,
/// so the model never writes Block Kit itself. The app checks Slack's limits and decides which buttons
/// exist, so malformed or injected arguments can neither break the reply nor add arbitrary actions.
struct SlackUI: Decodable, Equatable {
    struct Card: Decodable, Equatable {
        var title: String?
        var subtitle: String?
        var body: String?
        /// An `https` link, shown as an Open button.
        var url: String?
        /// A follow-up question, shown as a button that asks it in the thread.
        var ask: String?
    }

    var cards: [Card]

    static let toolName = "show_cards"
    static let openActionId = "slack_ui_open"
    static let askActionId = "slack_ui_ask"

    /// Builds a card for one item or a carousel for several, enforcing the card block's limits.
    func blocks() -> [Block] {
        let cards = cards
            .filter { !($0.title ?? "").isEmpty || !($0.body ?? "").isEmpty }
            .prefix(10)
            .map(Self.cardBlock)
        switch cards.count {
        case 0: return []
        case 1: return [.card(cards[0])]
        default: return [.carousel(CarouselBlock(elements: cards))]
        }
    }

    private static func cardBlock(_ card: Card) -> CardBlock {
        var actions: [ActionElementType] = []
        if let link = card.url, let url = URL(string: link), url.scheme == "https", link.count <= 3000 {
            actions.append(.button(ButtonElement(text: "Open", actionId: openActionId, url: url)))
        }
        if let ask = card.ask, !ask.isEmpty {
            actions.append(.button(ButtonElement(
                text: "Ask about this",
                actionId: askActionId,
                value: truncated(ask, to: 2000),
            )))
        }
        return CardBlock(
            title: card.title.map { TextObject(type: .plainText, text: truncated($0, to: 150)) },
            subtitle: card.subtitle.map { TextObject(type: .plainText, text: truncated($0, to: 150)) },
            body: card.body.map { TextObject(type: .mrkdwn, text: truncated($0, to: 200)) },
            actions: actions.isEmpty ? nil : actions,
        )
    }

    private static func truncated(_ text: String, to limit: Int) -> String {
        text.count > limit ? text.prefix(limit - 1) + "…" : text
    }
}

extension SlackUI {
    /// Decodes tool arguments, or throws a message the agent can act on.
    init(arguments: Data) throws {
        do {
            self = try JSONDecoder().decode(SlackUI.self, from: arguments)
        } catch {
            throw InvalidArguments(message: "Pass {\"cards\": [...]}, where each card is an object of strings.")
        }
        guard !blocks().isEmpty else {
            throw InvalidArguments(message: "Give at least one card a title or a body.")
        }
    }

    struct InvalidArguments: Error {
        let message: String
    }
}

extension SlackUI {
    /// The `ask_user` tool's schema allows two to five options.
    static let maxOptions = 5

    /// The button for option `index`. Slack rejects a block whose elements share an `action_id`.
    static func choiceActionId(_ index: Int) -> String {
        "ask_user_choice_\(index)"
    }

    /// The question and one button per option, each with its own `action_id` and the question's ID as
    /// its value.
    static func questionBlocks(id: String, question: String, options: [String], userId: String) -> [Block] {
        [
            .section(SectionBlock(text: TextObject(type: .mrkdwn, text: "<@\(userId)> \(question)"))),
            .actions(ActionsBlock(
                elements: options.prefix(maxOptions).enumerated().map { index, option in
                    .button(ButtonElement(
                        text: TextObject(type: .plainText, text: String(option.prefix(75))),
                        actionId: choiceActionId(index),
                        value: id,
                    ))
                },
                blockId: id,
            )),
        ]
    }

    static func questionResultBlocks(question: String, summary: String) -> [Block] {
        [.section(SectionBlock(text: TextObject(type: .mrkdwn, text: "\(question)\n\(summary)")))]
    }
}
