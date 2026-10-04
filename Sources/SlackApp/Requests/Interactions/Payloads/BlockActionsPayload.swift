import Foundation
import OpenAPIRuntime
import SlackBlockKit
import SlackModels

/// https://docs.slack.dev/reference/interaction-payloads/block_actions-payload#fields
public struct BlockActionsPayload: InteractivePayloadProtocol, Decodable, Sendable {
    /// "block_actions"
    public let _type: String
    public let triggerId: String?
    public let user: User
    public let team: Team
    public let enterprise: Enterprise?
    public let container: Container
    public let apiAppId: String?
    /// Use with views.update/views.publish concurrency control
    public let hash: String?
    public let actions: [ActionElementType]?
    public let channel: Channel?
    public let message: Message?
    /// Includes all stateful elements, not only input blocks
    public let state: StateValuesObject?
    public let view: View?
    /// Function-only metadata
    public let functionData: FunctionData?
    /// Function-only interactivity context
    public let interactivity: Interactivity?
    /// Function-only just-in-time token
    public let botAccessToken: String?
    /// Deprecated for functions, available for non-functions
    public let responseUrl: URL?

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case triggerId = "trigger_id"
        case user
        case team
        case enterprise
        case container
        case apiAppId = "api_app_id"
        case hash
        case actions
        case channel
        case message
        case state
        case view
        case functionData = "function_data"
        case interactivity
        case botAccessToken = "bot_access_token"
        case responseUrl = "response_url"
    }
}

@available(*, deprecated, renamed: "BlockActionsPayload")
public typealias BlockActionsPaylaod = BlockActionsPayload

extension BlockActionsPayload {
    /// The `callback_id` of the view that contains the actions, or `nil` for actions outside a view, such as message buttons.
    public var callbackId: String? {
        view?.callbackId
    }
}

extension BlockActionsPayload {
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
}
