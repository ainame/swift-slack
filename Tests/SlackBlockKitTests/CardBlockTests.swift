import Foundation
@testable import SlackBlockKit
import Testing

private let cardJSON = #"{"type":"card","icon":{"type":"image","image_url":"https://example.com/icon.png","alt_text":"Company logo"},"title":{"type":"mrkdwn","text":"Sample Company","verbatim":false},"subtitle":{"type":"mrkdwn","text":"A short tagline","verbatim":false},"hero_image":{"type":"image","image_url":"https://example.com/hero.png","alt_text":"Hero banner"},"body":{"type":"mrkdwn","text":"Body text.","verbatim":false},"subtext":{"type":"plain_text","text":"Subtext"},"actions":[{"type":"button","text":{"type":"plain_text","text":"Click me","emoji":false},"action_id":"sample_button"}],"block_id":"c1"}"#

private func jsonObject(_ json: String) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
}

@Test
func `Card block decodes and round-trips`() throws {
    let block = try JSONDecoder().decode(Block.self, from: Data(cardJSON.utf8))

    guard case let .card(card) = block else {
        Issue.record("Expected .card, got \(block)")
        return
    }
    #expect(card.title?.text == "Sample Company")
    #expect(card.heroImage?.altText == "Hero banner")
    #expect(card.icon?.altText == "Company logo")
    #expect(card.slackIcon == nil)
    #expect(card.subtext?.text == "Subtext")
    #expect(card.blockId == "c1")
    guard case .button = card.actions?.first else {
        Issue.record("Expected button action")
        return
    }

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try jsonObject(cardJSON)))
}

@Test
func `Card block with slack icon round-trips`() throws {
    let json = #"{"type":"card","slack_icon":{"type":"icon","name":"star"},"title":{"type":"plain_text","text":"T"}}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))
    guard case let .card(card) = block else {
        Issue.record("Expected .card, got \(block)")
        return
    }
    #expect(card.slackIcon?.name == "star")
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try jsonObject(json)))
}

@Test
func `Carousel block decodes and round-trips`() throws {
    let json = #"{"type":"carousel","elements":[\#(cardJSON),{"type":"card","title":{"type":"mrkdwn","text":"Example card","verbatim":false}}],"block_id":"car1"}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .carousel(carousel) = block else {
        Issue.record("Expected .carousel, got \(block)")
        return
    }
    #expect(carousel.elements.count == 2)
    #expect(carousel.blockId == "car1")

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try jsonObject(json)))
}
