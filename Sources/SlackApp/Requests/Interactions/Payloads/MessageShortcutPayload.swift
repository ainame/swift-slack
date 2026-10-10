import Foundation
import SlackClient

/// https://docs.slack.dev/reference/interaction-payloads/shortcuts-interaction-payload
public struct MessageShortcutPayload: InteractivePayloadProtocol, Decodable, Sendable {
    /// "shortcut"
    public let _type: String
    public let callbackId: String?
    public let triggerId: String
    public let user: User
    public let team: Team
    public let channel: Channel
    public let message: Message
    public let responseUrl: URL

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case callbackId = "callback_id"
        case triggerId = "trigger_id"
        case user
        case team
        case channel
        case message
        case responseUrl = "response_url"
    }
}
