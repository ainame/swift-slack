import Foundation
import OpenAPIRuntime
import SlackBlockKit
import SlackClient

/// https://docs.slack.dev/reference/interaction-payloads/view-interactions-payload#view_submission
public struct ViewSubmissionPayload: InteractivePayloadProtocol, Decodable, Sendable {
    /// "view_submission"
    public let _type: String
    public let enterprise: Enterprise?
    public let team: Team
    public let user: User
    public let apiAppId: String?
    public let triggerId: String?
    /// Use with views.update/views.publish concurrency control
    public let hash: String?
    public let view: View
    /// Generated only for `conversations_select` / `channels_select` with `response_url_enabled: true`.
    public let responseUrls: [ResponseUrl]?
    /// Function-only metadata
    public let functionData: FunctionData?
    /// Function-only interactivity context
    public let interactivity: Interactivity?
    /// Function-only just-in-time token
    public let botAccessToken: String?

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case enterprise
        case team
        case user
        case apiAppId = "api_app_id"
        case triggerId = "trigger_id"
        case hash
        case view
        case responseUrls = "response_urls"
        case functionData = "function_data"
        case interactivity
        case botAccessToken = "bot_access_token"
    }
}

extension ViewSubmissionPayload {
    public var callbackId: String? {
        view.callbackId
    }
}

extension ViewSubmissionPayload {
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

    public struct Interactivity: Decodable, Hashable, Sendable {
        public let interactivityPointer: String?
        public let interactor: Interactor?

        private enum CodingKeys: String, CodingKey {
            case interactivityPointer = "interactivity_pointer"
            case interactor
        }

        public struct Interactor: Decodable, Hashable, Sendable {
            public let id: String?
            public let secret: String?
        }
    }

    public struct ResponseUrl: Decodable, Hashable, Sendable {
        public let blockId: String?
        public let actionId: String?
        public let channelId: String?
        public let responseUrl: URL?

        private enum CodingKeys: String, CodingKey {
            case blockId = "block_id"
            case actionId = "action_id"
            case channelId = "channel_id"
            case responseUrl = "response_url"
        }
    }
}
