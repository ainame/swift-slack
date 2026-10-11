import Foundation
@testable import SlackBlockKit
import Testing

@Test
func `URL input element in input block decodes and round-trips`() throws {
    let json = #"{"type":"input","element":{"type":"url_text_input","action_id":"url_text_input-action","initial_value":"https://example.com","focus_on_load":true,"placeholder":{"type":"plain_text","text":"Enter a URL"},"dispatch_action_config":{"trigger_actions_on":["on_enter_pressed"]}},"label":{"type":"plain_text","text":"Label","emoji":true}}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .input(input) = block, case let .urlInput(element) = input.element else {
        Issue.record("Expected input block with url input, got \(block)")
        return
    }
    #expect(element.actionId == "url_text_input-action")
    #expect(element.initialValue == "https://example.com")
    #expect(element.focusOnLoad == true)

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)))
}
