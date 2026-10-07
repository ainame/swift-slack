import Foundation

/// https://docs.slack.dev/reference/interaction-payloads
public struct InteractiveEnvelope: Decodable, Hashable, Sendable {
    public let _type: String
    public let body: InteractivePayload

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let _type = try container.decode(String.self, forKey: ._type)
        self._type = _type

        switch _type {
        case "shortcut":
            body = try .shortcut(GlobalShortcutPayload(from: decoder))
        case "message_action":
            body = try .messageAction(MessageShortcutPayload(from: decoder))
        case "block_actions":
            body = try .blockActions(BlockActionsPayload(from: decoder))
        case "view_submission":
            body = try .viewSubmission(ViewSubmissionPayload(from: decoder))
        case "view_closed":
            body = try .viewClosed(ViewClosedPayload(from: decoder))
        case "block_suggestion":
            body = try .blockSuggestion(BlockSuggestionPayload(from: decoder))
        default:
            body = .unsupported(_type)
        }
    }
}
