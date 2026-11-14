import Foundation

public struct ButtonElement: Codable, Hashable, Sendable {
    public let type: String
    public let text: TextObject
    public let actionId: String?
    public let url: URL?
    public let value: String?
    public let style: ButtonStyle?
    public let confirm: ConfirmationDialogObject?
    public let accessibilityLabel: String?
    /// Prompt sent to Slackbot on click when Slackbot AI is available to the user. Maximum 4000 characters.
    public let agentPrompt: String?
    /// Text shown in the Slackbot message. Requires a prompt and defaults to the button text.
    public let agentPromptDisplay: String?
    /// Users who can see this button. If omitted, the button is visible to all users.
    public let visibleToUserIds: [String]?

    public init(
        text: TextObject,
        actionId: String? = nil,
        url: URL? = nil,
        value: String? = nil,
        style: ButtonStyle? = nil,
        confirm: ConfirmationDialogObject? = nil,
        accessibilityLabel: String? = nil,
        agentPrompt: String? = nil,
        agentPromptDisplay: String? = nil,
        visibleToUserIds: [String]? = nil,
    ) {
        type = "button"
        self.text = text
        self.actionId = actionId
        self.url = url
        self.value = value
        self.style = style
        self.confirm = confirm
        self.accessibilityLabel = accessibilityLabel
        self.agentPrompt = agentPrompt
        self.agentPromptDisplay = agentPromptDisplay
        self.visibleToUserIds = visibleToUserIds
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case actionId = "action_id"
        case url
        case value
        case style
        case confirm
        case accessibilityLabel = "accessibility_label"
        case agentPrompt = "agent_prompt"
        case agentPromptDisplay = "agent_prompt_display"
        case visibleToUserIds = "visible_to_user_ids"
    }
}

public enum ButtonStyle: String, Codable, Hashable, Sendable {
    case primary
    case danger
}
