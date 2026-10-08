#if SocketMode
import Foundation
import SlackBlockKit
import WSClient

enum SocketModeAcknowledger {
    static func makeAck(envelopeId: String, writer: WebSocketOutboundWriter) -> Ack {
        makeAck(envelopeId: envelopeId) { text in
            try await writer.write(.text(text))
        }
    }

    /// Builds an `Ack` that encodes each acknowledgement for `envelopeId` and passes the JSON text to `write`.
    static func makeAck(envelopeId: String, write: @escaping @Sendable (String) async throws -> Void) -> Ack {
        @Sendable func send(_ payload: some Encodable) async throws {
            try await write(encode(payload))
        }

        return Ack(
            basicHandler: {
                try await send(SocketModeAcknowledgementMessage(envelopeId: envelopeId))
            },
            viewHandler: { responseAction, view in
                try await send(SocketModeViewAck(
                    envelopeId: envelopeId,
                    payload: .init(responseAction: responseAction, view: view),
                ))
            },
            errorHandler: { errors in
                try await send(SocketModeErrorAck(
                    envelopeId: envelopeId,
                    payload: .init(responseAction: "errors", errors: errors),
                ))
            },
            optionsHandler: { response in
                try await send(SocketModeOptionsAck(envelopeId: envelopeId, payload: response))
            },
        )
    }

    static func sendBasicAck(envelopeId: String, writer: WebSocketOutboundWriter) async throws {
        try await send(SocketModeAcknowledgementMessage(envelopeId: envelopeId), writer: writer)
    }

    private static func send(_ payload: some Encodable, writer: WebSocketOutboundWriter) async throws {
        try await writer.write(.text(encode(payload)))
    }

    private static func encode(_ payload: some Encodable) throws -> String {
        try String(decoding: JSONEncoder().encode(payload), as: UTF8.self)
    }
}

private struct SocketModeViewAck: Encodable {
    let envelopeId: String
    let payload: Payload

    struct Payload: Encodable {
        let responseAction: String
        let view: View?

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
