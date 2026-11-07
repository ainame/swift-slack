import Foundation
import OpenAPIRuntime
import SlackBlockKit
import SlackClient

/// Sent when a user types in an external select menu, so the app can respond with options.
///
/// Acknowledge with ``Ack/callAsFunction(options:)`` or ``Ack/callAsFunction(optionGroups:)``.
///
/// https://docs.slack.dev/reference/interaction-payloads/block_suggestion-payload
public struct BlockSuggestionPayload: InteractivePayloadProtocol, Decodable, Sendable {
    /// "block_suggestion"
    public let _type: String
    public let enterprise: Enterprise?
    public let team: Team
    public let user: User
    public let container: Container
    public let apiAppId: String?
    /// The `action_id` of the select menu.
    public let actionId: String
    /// The `block_id` of the block that contains the select menu.
    public let blockId: String?
    /// The text the user has typed so far.
    public let value: String
    public let channel: Channel?
    public let message: Message?
    public let view: View?
    public let isEnterpriseInstall: Bool?
    /// Function-only metadata
    public let functionData: FunctionData?
    /// Function-only just-in-time token
    public let botAccessToken: String?

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case enterprise
        case team
        case user
        case container
        case apiAppId = "api_app_id"
        case actionId = "action_id"
        case blockId = "block_id"
        case value
        case channel
        case message
        case view
        case isEnterpriseInstall = "is_enterprise_install"
        case functionData = "function_data"
        case botAccessToken = "bot_access_token"
    }
}

extension BlockSuggestionPayload {
    /// The `callback_id` of the view that contains the select menu, or `nil` for a menu in a message.
    public var callbackId: String? {
        view?.callbackId
    }
}

extension BlockSuggestionPayload {
    public struct FunctionData: Decodable, Hashable, Sendable {
        public let executionId: String?
        public let function: Function?
        public let inputs: OpenAPIObjectContainer?

        private enum CodingKeys: String, CodingKey {
            case executionId = "execution_id"
            case function
            case inputs
        }

        public struct Function: Decodable, Hashable, Sendable {
            public let callbackId: String?

            private enum CodingKeys: String, CodingKey {
                case callbackId = "callback_id"
            }
        }
    }
}
