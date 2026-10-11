import Foundation
import SlackKit

/// The `slack-ui` block an agent may end its answer with: a small vocabulary that the app turns into
/// Block Kit, so the model never writes Block Kit itself. The app checks Slack's limits and decides which
/// buttons exist, so a malformed or injected block can neither break the reply nor add arbitrary actions.
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

    static let fence = "```slack-ui"
    static let openActionId = "slack_ui_open"
    static let askActionId = "slack_ui_ask"

    /// Tells the agent how to request cards.
    static let instructions = """
    When a few items deserve to stand out, such as files, links, or options to explore next, you may end \
    your answer with one fenced block that Slack renders as cards:

    ```slack-ui
    {"cards": [{"title": "Short title", "subtitle": "Optional", "body": "One or two sentences", \
    "url": "https://example.com", "ask": "A follow-up question the person can send with one click"}]}
    ```

    Use at most 10 cards. Every field is optional, but give each card a title or a body. Keep titles and \
    subtitles under 150 characters and bodies under 200. `url` must start with https://. Write nothing \
    after the block, and leave it out when plain text is enough.
    """

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

/// Separates a trailing `slack-ui` block from streamed answer text.
///
/// Text before the fence passes through as it arrives. A tail that could be the start of the fence is held
/// back until the next delta shows whether it is, and everything after the fence is kept for ``finish()``.
struct SlackUIExtractor {
    private var pending = ""
    private var source: String?

    /// Returns the part of `text` to stream now.
    mutating func consume(_ text: String) -> String {
        if source != nil {
            source? += text
            return ""
        }
        let combined = pending + text
        if let fence = combined.range(of: SlackUI.fence) {
            source = String(combined[fence.upperBound...])
            pending = ""
            return String(combined[..<fence.lowerBound])
        }
        let held = Self.longestSuffix(of: combined, startingFence: SlackUI.fence)
        pending = String(combined.suffix(held))
        return String(combined.dropLast(held))
    }

    /// Returns the text still to stream and the parsed block, or `nil` when there was none or it was invalid.
    mutating func finish() -> (text: String, ui: SlackUI?) {
        defer {
            pending = ""
            source = nil
        }
        guard let source else {
            return (pending, nil)
        }
        let parts = source.components(separatedBy: "```")
        let json = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = parts.count > 1 ? parts.dropFirst().joined(separator: "```") : ""
        let ui = try? JSONDecoder().decode(SlackUI.self, from: Data(json.utf8))
        return (trailing.trimmingCharacters(in: .whitespacesAndNewlines), ui)
    }

    private static func longestSuffix(of text: String, startingFence fence: String) -> Int {
        for length in stride(from: min(text.count, fence.count - 1), to: 0, by: -1)
            where fence.hasPrefix(text.suffix(length)) {
            return length
        }
        return 0
    }
}
