#if SocketMode
import Foundation
@testable import SlackApp
import SlackBlockKit
import Testing

struct SocketModeAcknowledgerTests {
    @Test func `clear acknowledgement omits the view`() async throws {
        actor Messages {
            private(set) var texts: [String] = []

            func append(_ text: String) {
                texts.append(text)
            }
        }

        let messages = Messages()
        let ack = SocketModeAcknowledger.makeAck(envelopeId: "env-1") { text in
            await messages.append(text)
        }

        try await ack(responseAction: .clear)

        let text = try #require(await messages.texts.first)
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
        #expect(json == ["envelope_id": "env-1", "payload": ["response_action": "clear"]])
    }

    @Test func `options acknowledgement wraps the options in the envelope payload`() throws {
        let ack = SocketModeOptionsAck(
            envelopeId: "env-1",
            payload: OptionsResponse(
                options: [OptionObject(text: TextObject(type: .plainText, text: "Ann"), value: "U1")],
                optionGroups: nil,
            ),
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ack)) as? NSDictionary

        #expect(json == [
            "envelope_id": "env-1",
            "payload": [
                "options": [["text": ["type": "plain_text", "text": "Ann"], "value": "U1"]],
            ],
        ])
    }
}
#endif
