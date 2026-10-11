import Foundation
@testable import SlackBlockKit
import Testing

@Test
func `Alert block decodes and round-trips`() throws {
    let json = #"{"type":"alert","text":{"type":"mrkdwn","text":"The work is mysterious and important.","verbatim":false},"level":"info","block_id":"a1"}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .alert(alert) = block else {
        Issue.record("Expected .alert, got \(block)")
        return
    }
    #expect(alert.level == .info)
    #expect(alert.blockId == "a1")
    #expect(alert.text.text == "The work is mysterious and important.")

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)))
}
