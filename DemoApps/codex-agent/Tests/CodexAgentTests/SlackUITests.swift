@testable import CodexAgent
import Foundation
import SlackKit
import Testing

struct SlackUIExtractorTests {
    @Test
    func `passes text without a fence through`() {
        var extractor = SlackUIExtractor()
        let streamed = ["Hello ", "world"].map { extractor.consume($0) }.joined()
        let finished = extractor.finish()
        #expect(streamed + finished.text == "Hello world")
        #expect(finished.ui == nil)
    }

    @Test
    func `separates a fence split across deltas`() {
        var extractor = SlackUIExtractor()
        let deltas = ["Answer.\n\n``", "`slack", "-ui\n{\"cards\": [{\"title\": \"A\"}]}", "\n```"]
        let streamed = deltas.map { extractor.consume($0) }.joined()
        let finished = extractor.finish()
        #expect(streamed == "Answer.\n\n")
        #expect(finished.text == "")
        #expect(finished.ui == SlackUI(cards: [.init(title: "A")]))
    }

    @Test
    func `releases held-back backticks that start another code block`() {
        var extractor = SlackUIExtractor()
        var streamed = extractor.consume("Run:\n``")
        #expect(streamed == "Run:\n")
        streamed += extractor.consume("`swift\nprint(1)\n```")
        #expect(streamed + extractor.finish().text == "Run:\n```swift\nprint(1)\n```")
    }

    @Test
    func `drops an invalid block but keeps text after it`() {
        var extractor = SlackUIExtractor()
        _ = extractor.consume("Hi\n```slack-ui\n{not json}\n```\nBye")
        let finished = extractor.finish()
        #expect(finished.ui == nil)
        #expect(finished.text == "Bye")
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
