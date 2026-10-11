import Codex
@testable import CodexAgent
import Foundation
import SlackKit
import Testing

struct SlackUIArgumentsTests {
    @Test
    func `decodes cards from tool arguments`() throws {
        let ui = try SlackUI(arguments: Data(#"{"cards": [{"title": "A", "url": "https://example.com"}]}"#.utf8))
        #expect(ui == SlackUI(cards: [.init(title: "A", url: "https://example.com")]))
    }

    @Test(arguments: [
        #"{"items": []}"#,
        #"{"cards": [{"title": 1}]}"#,
        #"{"cards": [{"subtitle": "no title or body"}]}"#,
    ])
    func `rejects arguments without a usable card`(json: String) {
        #expect(throws: SlackUI.InvalidArguments.self) {
            try SlackUI(arguments: Data(json.utf8))
        }
    }
}

struct CardsToolTests {
    @Test
    func `accepts valid cards and rejects invalid ones with a message for the agent`() async {
        let valid = await CardsTool.handle(call(["cards": [["title": "A"]]]))
        #expect(valid.success)

        let invalid = await CardsTool.handle(call(["cards": []]))
        #expect(!invalid.success)
        #expect(invalid.contentItems == [.inputText(.init(text: "Give at least one card a title or a body.", type: .inputText))])
    }

    @Test
    func `rejects unknown tools`() async {
        #expect(await !CardsTool.handle(call([:], tool: "rm_rf")).success)
    }

    @Test
    func `reads cards only from successful show_cards calls`() {
        let arguments: JSONValue = ["cards": [["title": "A"]]]
        #expect(CardsTool.cards(from: item(arguments, success: true)) == SlackUI(cards: [.init(title: "A")]))
        #expect(CardsTool.cards(from: item(arguments, success: false)) == nil)
        #expect(CardsTool.cards(from: item(arguments, success: true, tool: "other")) == nil)
    }

    private func call(_ arguments: JSONValue, tool: String = SlackUI.toolName) -> DynamicToolCallParams {
        DynamicToolCallParams(arguments: arguments, callId: "call-1", threadId: "thread", tool: tool, turnId: "turn")
    }

    private func item(_ arguments: JSONValue, success: Bool, tool: String = SlackUI.toolName) -> DynamicToolCallThreadItem {
        DynamicToolCallThreadItem(
            arguments: arguments,
            id: "call-1",
            status: success ? .completed : .failed,
            success: success,
            tool: tool,
            type: .dynamicToolCall,
        )
    }
}

struct SlackUIBlocksTests {
    @Test
    func `builds one card for one item and a carousel for several`() {
        let one = SlackUI(cards: [.init(title: "A")]).blocks()
        guard case .card? = one.first else {
            Issue.record("expected a card, got \(one)")
            return
        }

        let several = SlackUI(cards: Array(repeating: .init(title: "A"), count: 12)).blocks()
        guard case let .carousel(carousel)? = several.first else {
            Issue.record("expected a carousel, got \(several)")
            return
        }
        #expect(carousel.elements.count == 10)
    }

    @Test
    func `skips cards without a title or body`() {
        #expect(SlackUI(cards: [.init(subtitle: "only"), .init(url: "https://example.com")]).blocks().isEmpty)
    }

    @Test
    func `adds buttons only for https links and follow-up questions`() throws {
        let card = try #require(card(from: SlackUI(cards: [
            .init(title: "A", url: "http://example.com", ask: "More?"),
        ])))
        let actions = card.actions ?? []
        #expect(actions.count == 1)
        guard case let .button(button)? = actions.first else {
            Issue.record("expected a button")
            return
        }
        #expect(button.actionId == SlackUI.askActionId)
        #expect(button.value == "More?")
    }

    @Test
    func `truncates fields to the card block's limits`() throws {
        let long = String(repeating: "a", count: 500)
        let card = try #require(card(from: SlackUI(cards: [.init(title: long, subtitle: long, body: long)])))
        #expect(card.title?.text.count == 150)
        #expect(card.subtitle?.text.count == 150)
        #expect(card.body?.text.count == 200)
    }

    private func card(from ui: SlackUI) -> CardBlock? {
        guard case let .card(card)? = ui.blocks().first else { return nil }
        return card
    }
}
