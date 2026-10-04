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
    /// The interacted elements and their selected values.
    public let blockActions: [Action]
    private let elementActions: [ActionElementType]?
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
        blockActions = try container.decodeIfPresent([Action].self, forKey: .actions) ?? []
        elementActions = try container.decodeIfPresent([LossyActionElement].self, forKey: .actions)?
            .compactMap(\.element)
        channel = try container.decodeIfPresent(Channel.self, forKey: .channel)
        message = try container.decodeIfPresent(Message.self, forKey: .message)
        state = try container.decodeIfPresent(StateValuesObject.self, forKey: .state)
        view = try container.decodeIfPresent(View.self, forKey: .view)
        functionData = try container.decodeIfPresent(FunctionData.self, forKey: .functionData)
        interactivity = try container.decodeIfPresent(Interactivity.self, forKey: .interactivity)
        botAccessToken = try container.decodeIfPresent(String.self, forKey: .botAccessToken)
        responseUrl = try container.decodeIfPresent(URL.self, forKey: .responseUrl)
    }

    /// The interacted elements decoded as Block Kit element definitions.
    ///
    /// Element definitions do not carry `block_id` or selected values, and elements that cannot be decoded
    /// this way, such as checkboxes without their `options`, are skipped.
    @available(*, deprecated, message: "Use blockActions, which carries each action's action_id, block_id, and selected values. actions will be removed in a 2027 release.")
    public var actions: [ActionElementType]? {
        elementActions
    }
}

/// Decodes an element of `actions` as a Block Kit element definition, or `nil` when it cannot be decoded that way.
private struct LossyActionElement: Decodable {
    let element: ActionElementType?

    init(from decoder: any Decoder) throws {
        element = try? ActionElementType(from: decoder)
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
        blockActions.contains { $0.matches(actionId: actionId, blockId: blockId) }
    }
}

extension BlockActionsPayload {
    /// An interacted element in a `block_actions` payload, as listed in ``BlockActionsPayload/blockActions``.
    ///
    /// Unlike a Block Kit element definition, this carries the selected values and omits the element's
    /// options. Fields that do not apply to the element's `type` are `nil`, so element types that this
    /// model does not cover still decode.
    public struct Action: Decodable, Hashable, Sendable {
        /// The element type, such as "button", "static_select", or "plain_text_input".
        public let _type: String
        public let actionId: String
        public let blockId: String?
        public let actionTs: String?
        /// The button text
        public let text: TextObject?
        /// The button value, or the text entered in a text input
        public let value: String?
        public let style: String?
        /// The link button URL, or `nil` when it is not a valid URL
        public let url: URL?
        public let selectedOption: StateValuesObject.SelectedOption?
        public let selectedOptions: [StateValuesObject.SelectedOption]?
        public let selectedUser: String?
        public let selectedUsers: [String]?
        public let selectedConversation: String?
        public let selectedConversations: [String]?
        public let selectedChannel: String?
        public let selectedChannels: [String]?
        /// The date selected in a `datepicker`, formatted as `YYYY-MM-DD`
        public let selectedDate: String?
        /// The time selected in a `timepicker`, formatted as `HH:mm`
        public let selectedTime: String?
        /// The UNIX timestamp selected in a `datetimepicker`
        public let selectedDateTime: Int?
        /// The value of a `rich_text_input`, or `nil` when it contains elements that `RichTextBlock` cannot decode
        public let richTextValue: RichTextBlock?

        private enum CodingKeys: String, CodingKey {
            case _type = "type"
            case actionId = "action_id"
            case blockId = "block_id"
            case actionTs = "action_ts"
            case text
            case value
            case style
            case url
            case selectedOption = "selected_option"
            case selectedOptions = "selected_options"
            case selectedUser = "selected_user"
            case selectedUsers = "selected_users"
            case selectedConversation = "selected_conversation"
            case selectedConversations = "selected_conversations"
            case selectedChannel = "selected_channel"
            case selectedChannels = "selected_channels"
            case selectedDate = "selected_date"
            case selectedTime = "selected_time"
            case selectedDateTime = "selected_date_time"
            case richTextValue = "rich_text_value"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            _type = try container.decode(String.self, forKey: ._type)
            actionId = try container.decode(String.self, forKey: .actionId)
            blockId = try container.decodeIfPresent(String.self, forKey: .blockId)
            actionTs = try container.decodeIfPresent(String.self, forKey: .actionTs)
            text = try container.decodeIfPresent(TextObject.self, forKey: .text)
            value = try container.decodeIfPresent(String.self, forKey: .value)
            style = try container.decodeIfPresent(String.self, forKey: .style)
            // An empty or malformed link button URL should not drop the whole interaction.
            url = try? container.decodeIfPresent(URL.self, forKey: .url)
            selectedOption = try container.decodeIfPresent(StateValuesObject.SelectedOption.self, forKey: .selectedOption)
            selectedOptions = try container.decodeIfPresent([StateValuesObject.SelectedOption].self, forKey: .selectedOptions)
            selectedUser = try container.decodeIfPresent(String.self, forKey: .selectedUser)
            selectedUsers = try container.decodeIfPresent([String].self, forKey: .selectedUsers)
            selectedConversation = try container.decodeIfPresent(String.self, forKey: .selectedConversation)
            selectedConversations = try container.decodeIfPresent([String].self, forKey: .selectedConversations)
            selectedChannel = try container.decodeIfPresent(String.self, forKey: .selectedChannel)
            selectedChannels = try container.decodeIfPresent([String].self, forKey: .selectedChannels)
            selectedDate = try container.decodeIfPresent(String.self, forKey: .selectedDate)
            selectedTime = try container.decodeIfPresent(String.self, forKey: .selectedTime)
            selectedDateTime = try container.decodeIfPresent(Int.self, forKey: .selectedDateTime)
            // Rich text has many element types; an unsupported one should not drop the whole interaction.
            richTextValue = try? container.decodeIfPresent(RichTextBlock.self, forKey: .richTextValue)
        }

        func matches(actionId: String, blockId: String?) -> Bool {
            self.actionId == actionId && (blockId == nil || self.blockId == blockId)
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
