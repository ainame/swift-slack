#if Events
import Foundation
import SlackApp
import Testing

struct CodeChannelActionEventTests {
    @Test func `opaque action retains arbitrary JSON and participates in event equality`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/slack_code_fixtures/CodeChannelActionPayload.json"))
        let event = try JSONDecoder().decode(Event.self, from: data)
        guard case let .codeChannelAction(action) = event else {
            Issue.record("Expected a Code channel action")
            return
        }
        #expect(action._type == "code_channel_action")
        #expect(event.payload is CodeChannelActionEvent)
        let expected = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let encoded = try JSONEncoder().encode(action)
        let actual = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(actual == expected)
        let decodedAgain = try JSONDecoder().decode(Event.self, from: encoded)
        #expect(event == decodedAgain)
        let different = try JSONDecoder().decode(Event.self, from: Data(#"{"type":"code_channel_action","synthetic_text":"changed"}"#.utf8))
        #expect(event != different)
        #expect(Set([event, different]).count == 2)
    }
}
#endif
