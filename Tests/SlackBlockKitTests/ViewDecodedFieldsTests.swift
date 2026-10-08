import Foundation
@testable import SlackBlockKit
import Testing

struct ViewDecodedFieldsTests {
    @Test
    func `decode modal view hash`() throws {
        let view = try JSONDecoder().decode(View.self, from: Data("""
        {
          "type": "modal",
          "id": "V123",
          "hash": "1571318366.2468e46f",
          "title": { "type": "plain_text", "text": "Test" },
          "blocks": []
        }
        """.utf8))

        #expect(view.id == "V123")
        #expect(view.hash == "1571318366.2468e46f")
    }

    @Test
    func `decode home tab view hash`() throws {
        let view = try JSONDecoder().decode(View.self, from: Data("""
        {
          "type": "home",
          "id": "V456",
          "hash": "1571318367.abcdef12",
          "blocks": []
        }
        """.utf8))

        #expect(view.id == "V456")
        #expect(view.hash == "1571318367.abcdef12")
    }

    // Slack rejects `id`, `state`, and `hash` inside the `view` argument with `invalid_arguments`.
    @Test(arguments: [
        #"{"type":"modal","id":"V123","hash":"1.a","state":{"values":{}},"callback_id":"todo","title":{"type":"plain_text","text":"Test"},"blocks":[]}"#,
        #"{"type":"home","id":"V456","hash":"1.b","state":{"values":{}},"callback_id":"home","blocks":[]}"#,
    ])
    func `encoding a decoded view omits id, state, and hash`(json: String) throws {
        let view = try JSONDecoder().decode(View.self, from: Data(json.utf8))
        #expect(view.id != nil)
        #expect(view.state != nil)
        #expect(view.hash != nil)

        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any])

        #expect(encoded["id"] == nil)
        #expect(encoded["state"] == nil)
        #expect(encoded["hash"] == nil)
        #expect(encoded["callback_id"] as? String == view.callbackId)
    }
}
