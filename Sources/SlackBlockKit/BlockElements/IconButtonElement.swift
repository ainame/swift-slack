import Foundation

public struct IconButtonElement: Codable, Hashable, Sendable {
    public let type: String
    /// The icon name. `trash` is the only icon Slack currently supports.
    public let icon: String
    public let text: TextObject
    public let actionId: String?
    public let value: String?
    public let confirm: ConfirmationDialogObject?
    public let accessibilityLabel: String?
    public let visibleToUserIds: [String]?

    public init(
        icon: String,
        text: TextObject,
        actionId: String? = nil,
        value: String? = nil,
        confirm: ConfirmationDialogObject? = nil,
        accessibilityLabel: String? = nil,
        visibleToUserIds: [String]? = nil,
    ) {
        type = "icon_button"
        self.icon = icon
        self.text = text
        self.actionId = actionId
        self.value = value
        self.confirm = confirm
        self.accessibilityLabel = accessibilityLabel
        self.visibleToUserIds = visibleToUserIds
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case icon
        case text
        case actionId = "action_id"
        case value
        case confirm
        case accessibilityLabel = "accessibility_label"
        case visibleToUserIds = "visible_to_user_ids"
    }
}
