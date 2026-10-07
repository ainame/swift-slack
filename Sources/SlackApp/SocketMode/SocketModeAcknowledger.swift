#if SocketMode
import Foundation
import SlackBlockKit
import WSClient

enum SocketModeAcknowledger {
    static func makeAck(envelopeId: String, writer: WebSocketOutboundWriter) -> Ack {
        Ack(
            basicHandler: {
                try await sendBasicAck(envelopeId: envelopeId, writer: writer)
            },
            viewHandler: { responseAction, view in
                let payload = SocketModeViewAck(
                    envelopeId: envelopeId,
                    payload: .init(responseAction: responseAction.rawValue, view: view),
                )
                try await send(payload, writer: writer)
            },
            errorHandler: { errors in
                let payload = SocketModeErrorAck(
                    envelopeId: envelopeId,
                    payload: .init(responseAction: "errors", errors: errors),
                )
                try await send(payload, writer: writer)
            },
            optionsHandler: { response in
                try await send(SocketModeOptionsAck(envelopeId: envelopeId, payload: response), writer: writer)
            },
        )
    }

    static func sendBasicAck(envelopeId: String, writer: WebSocketOutboundWriter) async throws {
        try await send(SocketModeAcknowledgementMessage(envelopeId: envelopeId), writer: writer)
    }

    private static func send(_ payload: some Encodable, writer: WebSocketOutboundWriter) async throws {
        let data = try JSONEncoder().encode(payload)
        try await writer.write(.text(String(decoding: data, as: UTF8.self)))
    }
}

private struct SocketModeViewAck: Encodable {
    let envelopeId: String
    let payload: Payload

    struct Payload: Encodable {
        let responseAction: String
        let view: View

        private enum CodingKeys: String, CodingKey {
            case responseAction = "response_action"
            case view
        }
    }

    private enum CodingKeys: String, CodingKey {
        case envelopeId = "envelope_id"
        case payload
    }
}

struct SocketModeOptionsAck: Encodable {
    let envelopeId: String
    let payload: OptionsResponse

    private enum CodingKeys: String, CodingKey {
        case envelopeId = "envelope_id"
        case payload
    }
}

private struct SocketModeErrorAck: Encodable {
    let envelopeId: String
    let payload: Payload

    struct Payload: Encodable {
        let responseAction: String
        let errors: [String: String]

        private enum CodingKeys: String, CodingKey {
            case responseAction = "response_action"
            case errors
        }
    }

    private enum CodingKeys: String, CodingKey {
        case envelopeId = "envelope_id"
        case payload
    }
}
#endif
