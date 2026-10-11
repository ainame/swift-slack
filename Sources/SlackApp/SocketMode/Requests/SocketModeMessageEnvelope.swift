#if SocketMode
import Foundation
import SlackClient

public struct SocketModeMessageEnvelope: Decodable, Hashable, Sendable {
    public enum Payload: Decodable, Hashable, Sendable {
        case interactive(InteractiveEnvelope)
        case slashCommands(SlashCommandsPayload)
        #if Events
        case eventsApi(EventsApiEnvelope<Event>)
        #endif
        case unsupported(String)
    }

    public let envelopeId: String
    public let _type: String
    public let payload: Payload
    public let acceptsResponsePayload: Bool
    /// How many times Slack has retried an `events_api` envelope, or `nil` for the first delivery.
    public let retryAttempt: Int?
    /// Why Slack retried an `events_api` envelope, such as `timeout`, or `nil` for the first delivery.
    public let retryReason: String?

    public enum CodingKeys: String, CodingKey {
        case envelopeId = "envelope_id"
        case _type = "type"
        case payload
        case acceptsResponsePayload = "accepts_response_payload"
        case retryAttempt = "retry_attempt"
        case retryReason = "retry_reason"
    }

    init(
        envelopeId: String,
        _type: String,
        payload: Payload,
        acceptsResponsePayload: Bool,
        retryAttempt: Int? = nil,
        retryReason: String? = nil,
    ) {
        self.envelopeId = envelopeId
        self._type = _type
        self.payload = payload
        self.acceptsResponsePayload = acceptsResponsePayload
        self.retryAttempt = retryAttempt
        self.retryReason = retryReason
    }

    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        _type = try container.decode(String.self, forKey: CodingKeys._type)
        envelopeId = try container.decode(String.self, forKey: CodingKeys.envelopeId)
        acceptsResponsePayload = try container.decode(Bool.self, forKey: CodingKeys.acceptsResponsePayload)
        retryAttempt = try container.decodeIfPresent(Int.self, forKey: CodingKeys.retryAttempt)
        retryReason = try container.decodeIfPresent(String.self, forKey: CodingKeys.retryReason)

        switch _type {
        case "interactive":
            let interaction = try container.decode(InteractiveEnvelope.self, forKey: CodingKeys.payload)
            payload = .interactive(interaction)
        case "slash_commands":
            let payload = try container.decode(SlashCommandsPayload.self, forKey: CodingKeys.payload)
            self.payload = .slashCommands(payload)
        #if Events
        case "events_api":
            let event = try container.decode(EventsApiEnvelope<Event>.self, forKey: CodingKeys.payload)
            payload = .eventsApi(event)
        #endif
        default:
            payload = .unsupported(_type)
        }
    }
}
#endif
