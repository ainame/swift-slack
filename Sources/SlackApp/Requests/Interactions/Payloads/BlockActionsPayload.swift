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
    public let actions: [Action]?
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

    /// Returns whether any action has the given `action_id`, and the given `block_id` when one is specified.
    public func containsAction(_ actionId: String, blockId: String? = nil) -> Bool {
        actions?.contains { $0.matches(actionId: actionId, blockId: blockId) } ?? false
    }
}

extension BlockActionsPayload {
    /// An interacted element in a `block_actions` payload.
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
            url = try container.decodeIfPresent(URL.self, forKey: .url)
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
