#if SocketMode
import Foundation
@testable import SlackApp
import SlackBlockKit
import Testing

struct SocketModeAcknowledgerTests {
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
