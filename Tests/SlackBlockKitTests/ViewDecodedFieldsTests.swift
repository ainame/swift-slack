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

/// Guards `ModalView` and `HomeTabView`'s hand-written `encode(to:)`: decoding a view with every field set must set
/// every stored property, and encoding it must write every field except `id`, `state`, and `hash`, each under its
/// own key with its own value. A property added later fails this test until the fixture and `encode(to:)` include it.
/// Fixture values differ where they can, so a field written under another field's key fails too.
struct ViewEncodingCoverageTests {
    @Test
    func `modal view encodes every field except id, state, and hash`() throws {
        try expectCoverage(of: ModalView.self, json: """
        {
          "type": "modal",
          "title": { "type": "plain_text", "text": "Title" },
          "blocks": [],
          "close": { "type": "plain_text", "text": "Close" },
          "submit": { "type": "plain_text", "text": "Submit" },
          "private_metadata": "metadata",
          "callback_id": "callback",
          "clear_on_close": true,
          "notify_on_close": false,
          "external_id": "external",
          "submit_disabled": true,
          "state": { "values": {} },
          "id": "V123",
          "hash": "1.a"
        }
        """)
    }

    @Test
    func `home tab view encodes every field except id, state, and hash`() throws {
        try expectCoverage(of: HomeTabView.self, json: """
        {
          "type": "home",
          "blocks": [],
          "private_metadata": "metadata",
          "callback_id": "callback",
          "external_id": "external",
          "state": { "values": {} },
          "id": "V456",
          "hash": "1.b"
        }
        """)
    }

    private func expectCoverage<T: Codable>(of _: T.Type, json: String) throws {
        let view = try JSONDecoder().decode(T.self, from: Data(json.utf8))
        let properties = Mirror(reflecting: view).children
        for property in properties {
            let isNil = if case Optional<Any>.none = property.value { true } else { false }
            #expect(!isNil, "The fixture doesn't set \(property.label ?? "a property")")
        }

        let input = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any])
        #expect(input.count == properties.count)
        let expected = input.filter { !["id", "state", "hash"].contains($0.key) }
        #expect(NSDictionary(dictionary: encoded) == NSDictionary(dictionary: expected))
    }

    // Unset optional fields must be left out, not encoded as null.
    @Test(arguments: [
        #"{"type":"modal","title":{"type":"plain_text","text":"Title"},"blocks":[]}"#,
        #"{"type":"home","blocks":[]}"#,
    ])
    func `views without optional fields encode only the required ones`(json: String) throws {
        let view = try JSONDecoder().decode(View.self, from: Data(json.utf8))

        let input = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? NSDictionary

        #expect(encoded == input)
    }
}
