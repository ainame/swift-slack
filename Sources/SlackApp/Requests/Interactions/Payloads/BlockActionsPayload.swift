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
    /// The `action_id` and `block_id` of each element in `actions`, in the same order.
    public let actionIdentifiers: [ActionIdentifier]
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _type = try container.decode(String.self, forKey: ._type)
        triggerId = try container.decodeIfPresent(String.self, forKey: .triggerId)
        user = try container.decode(User.self, forKey: .user)
        team = try container.decode(Team.self, forKey: .team)
        enterprise = try container.decodeIfPresent(Enterprise.self, forKey: .enterprise)
        self.container = try container.decode(Container.self, forKey: .container)
        apiAppId = try container.decodeIfPresent(String.self, forKey: .apiAppId)
        hash = try container.decodeIfPresent(String.self, forKey: .hash)
        actions = try container.decodeIfPresent([ActionElementType].self, forKey: .actions)
        // Block Kit elements do not carry `block_id`, so decode the identifiers separately.
        actionIdentifiers = try container.decodeIfPresent([ActionIdentifier].self, forKey: .actions) ?? []
        channel = try container.decodeIfPresent(Channel.self, forKey: .channel)
        message = try container.decodeIfPresent(Message.self, forKey: .message)
        state = try container.decodeIfPresent(StateValuesObject.self, forKey: .state)
        view = try container.decodeIfPresent(View.self, forKey: .view)
        functionData = try container.decodeIfPresent(FunctionData.self, forKey: .functionData)
        interactivity = try container.decodeIfPresent(Interactivity.self, forKey: .interactivity)
        botAccessToken = try container.decodeIfPresent(String.self, forKey: .botAccessToken)
        responseUrl = try container.decodeIfPresent(URL.self, forKey: .responseUrl)
    }
}

@available(*, deprecated, renamed: "BlockActionsPayload")
public typealias BlockActionsPaylaod = BlockActionsPayload

extension BlockActionsPayload {
    /// The `callback_id` of the view that contains the actions, or `nil` for actions outside a view, such as message buttons.
    public var callbackId: String? {
        view?.callbackId
    }

    /// Returns whether any action has the given `action_id`, and the given `block_id` when one is specified.
    public func containsAction(_ actionId: String, blockId: String? = nil) -> Bool {
        actionIdentifiers.contains { $0.matches(actionId: actionId, blockId: blockId) }
    }
}

extension BlockActionsPayload {
    public struct ActionIdentifier: Decodable, Hashable, Sendable {
        public let actionId: String
        public let blockId: String?

        public init(actionId: String, blockId: String?) {
            self.actionId = actionId
            self.blockId = blockId
        }

        func matches(actionId: String, blockId: String?) -> Bool {
            self.actionId == actionId && (blockId == nil || self.blockId == blockId)
        }

        private enum CodingKeys: String, CodingKey {
            case actionId = "action_id"
            case blockId = "block_id"
        }
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
