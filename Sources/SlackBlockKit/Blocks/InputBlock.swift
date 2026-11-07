import Foundation
import OpenAPIRuntime

public struct InputBlock: Codable, Hashable, Sendable {
    public let type: String
    public let label: TextObject
    public let element: InputElementType
    public let blockId: String?
    public let dispatchAction: Bool?
    public let hint: TextObject?
    public let optional: Bool?

    public init(
        label: TextObject,
        element: InputElementType,
        blockId: String? = nil,
        dispatchAction: Bool? = nil,
        hint: TextObject? = nil,
        optional: Bool? = nil,
    ) {
        type = "input"
        self.label = label
        self.element = element
        self.blockId = blockId
        self.dispatchAction = dispatchAction
        self.hint = hint
        self.optional = optional
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case label
        case element
        case blockId = "block_id"
        case dispatchAction = "dispatch_action"
        case hint
        case optional
    }
}

public enum InputElementType: Codable, Hashable, Sendable {
    case checkboxes(CheckboxesElement)
    case datePicker(DatePickerElement)
    case datetimePicker(DatetimePickerElement)
    case emailInput(EmailInputElement)
    case fileInput(FileInputElement)
    case multiStaticSelect(MultiStaticSelectElement)
    case multiExternalSelect(MultiExternalSelectElement)
    case multiUsersSelect(MultiUsersSelectElement)
    case multiConversationsSelect(MultiConversationsSelectElement)
    case multiChannelsSelect(MultiChannelsSelectElement)
    case numberInput(NumberInputElement)
    case plainTextInput(PlainTextInputElement)
    case radioButtons(RadioButtonsElement)
    case richTextInput(RichTextInputElement)
    case staticSelect(StaticSelectElement)
    case externalSelect(ExternalSelectElement)
    case usersSelect(UsersSelectElement)
    case conversationsSelect(ConversationsSelectElement)
    case channelsSelect(ChannelsSelectElement)
    case timePicker(TimePickerElement)
    case urlInput(URLInputElement)
    case unknown(type: String, payload: OpenAPIObjectContainer)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "checkboxes":
            self = try .checkboxes(container.decode(CheckboxesElement.self))
        case "datepicker":
            self = try .datePicker(container.decode(DatePickerElement.self))
        case "datetimepicker":
            self = try .datetimePicker(container.decode(DatetimePickerElement.self))
        case "email_text_input":
            self = try .emailInput(container.decode(EmailInputElement.self))
        case "file_input":
            self = try .fileInput(container.decode(FileInputElement.self))
        case "multi_static_select":
            self = try .multiStaticSelect(container.decode(MultiStaticSelectElement.self))
        case "multi_external_select":
            self = try .multiExternalSelect(container.decode(MultiExternalSelectElement.self))
        case "multi_users_select":
            self = try .multiUsersSelect(container.decode(MultiUsersSelectElement.self))
        case "multi_conversations_select":
            self = try .multiConversationsSelect(container.decode(MultiConversationsSelectElement.self))
        case "multi_channels_select":
            self = try .multiChannelsSelect(container.decode(MultiChannelsSelectElement.self))
        case "number_input":
            self = try .numberInput(container.decode(NumberInputElement.self))
        case "plain_text_input":
            self = try .plainTextInput(container.decode(PlainTextInputElement.self))
        case "radio_buttons":
            self = try .radioButtons(container.decode(RadioButtonsElement.self))
        case "rich_text_input":
            self = try .richTextInput(container.decode(RichTextInputElement.self))
        case "static_select":
            self = try .staticSelect(container.decode(StaticSelectElement.self))
        case "external_select":
            self = try .externalSelect(container.decode(ExternalSelectElement.self))
        case "users_select":
            self = try .usersSelect(container.decode(UsersSelectElement.self))
        case "conversations_select":
            self = try .conversationsSelect(container.decode(ConversationsSelectElement.self))
        case "channels_select":
            self = try .channelsSelect(container.decode(ChannelsSelectElement.self))
        case "timepicker":
            self = try .timePicker(container.decode(TimePickerElement.self))
        case "url_text_input":
            self = try .urlInput(container.decode(URLInputElement.self))
        default:
            self = try .unknown(type: type, payload: OpenAPIObjectContainer(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .checkboxes(element):
            try container.encode(element)
        case let .datePicker(element):
            try container.encode(element)
        case let .datetimePicker(element):
            try container.encode(element)
        case let .emailInput(element):
            try container.encode(element)
        case let .fileInput(element):
            try container.encode(element)
        case let .multiStaticSelect(element):
            try container.encode(element)
        case let .multiExternalSelect(element):
            try container.encode(element)
        case let .multiUsersSelect(element):
            try container.encode(element)
        case let .multiConversationsSelect(element):
            try container.encode(element)
        case let .multiChannelsSelect(element):
            try container.encode(element)
        case let .numberInput(element):
            try container.encode(element)
        case let .plainTextInput(element):
            try container.encode(element)
        case let .radioButtons(element):
            try container.encode(element)
        case let .richTextInput(element):
            try container.encode(element)
        case let .staticSelect(element):
            try container.encode(element)
        case let .externalSelect(element):
            try container.encode(element)
        case let .usersSelect(element):
            try container.encode(element)
        case let .conversationsSelect(element):
            try container.encode(element)
        case let .channelsSelect(element):
            try container.encode(element)
        case let .timePicker(element):
            try container.encode(element)
        case let .urlInput(element):
            try container.encode(element)
        case let .unknown(type, payload):
            try container.encode(OpenAPIObjectContainer.unknown(type: type, payload: payload))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}
