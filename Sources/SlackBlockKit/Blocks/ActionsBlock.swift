import Foundation
import OpenAPIRuntime

public struct ActionsBlock: Codable, Hashable, Sendable {
    public let type: String
    public let elements: [ActionElementType]
    public let blockId: String?

    public init(elements: [ActionElementType], blockId: String? = nil) {
        type = "actions"
        self.elements = elements
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case elements
        case blockId = "block_id"
    }
}

public enum ActionElementType: Codable, Hashable, Sendable {
    case button(ButtonElement)
    case checkboxes(CheckboxesElement)
    case datePicker(DatePickerElement)
    case datetimePicker(DatetimePickerElement)
    case multiStaticSelect(MultiStaticSelectElement)
    case multiExternalSelect(MultiExternalSelectElement)
    case multiUsersSelect(MultiUsersSelectElement)
    case multiConversationsSelect(MultiConversationsSelectElement)
    case multiChannelsSelect(MultiChannelsSelectElement)
    case overflow(OverflowMenuElement)
    case radioButtons(RadioButtonsElement)
    case richTextInput(RichTextInputElement)
    case staticSelect(StaticSelectElement)
    case externalSelect(ExternalSelectElement)
    case usersSelect(UsersSelectElement)
    case conversationsSelect(ConversationsSelectElement)
    case channelsSelect(ChannelsSelectElement)
    case timePicker(TimePickerElement)
    case workflowButton(WorkflowButtonElement)
    case unknown(type: String, payload: OpenAPIObjectContainer)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "button":
            self = try .button(container.decode(ButtonElement.self))
        case "checkboxes":
            self = try .checkboxes(container.decode(CheckboxesElement.self))
        case "datepicker":
            self = try .datePicker(container.decode(DatePickerElement.self))
        case "datetimepicker":
            self = try .datetimePicker(container.decode(DatetimePickerElement.self))
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
        case "overflow":
            self = try .overflow(container.decode(OverflowMenuElement.self))
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
        case "workflow_button":
            self = try .workflowButton(container.decode(WorkflowButtonElement.self))
        default:
            self = try .unknown(type: type, payload: OpenAPIObjectContainer(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .button(element):
            try container.encode(element)
        case let .checkboxes(element):
            try container.encode(element)
        case let .datePicker(element):
            try container.encode(element)
        case let .datetimePicker(element):
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
        case let .overflow(element):
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
        case let .workflowButton(element):
            try container.encode(element)
        case let .unknown(type, payload):
            try container.encode(OpenAPIObjectContainer.unknown(type: type, payload: payload))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}
