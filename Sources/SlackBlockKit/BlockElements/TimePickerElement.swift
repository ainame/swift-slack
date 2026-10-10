import Foundation

public struct TimePickerElement: Codable, Hashable, Sendable {
    public let type: String
    public let actionId: String?
    public let initialTime: String?
    public let confirm: ConfirmationDialogObject?
    public let focusOnLoad: Bool?
    public let placeholder: TextObject?
    /// An IANA time zone name, such as `America/Chicago`, shown as a hint under the picker.
    public let timezone: String?

    public init(
        actionId: String? = nil,
        initialTime: String? = nil,
        confirm: ConfirmationDialogObject? = nil,
        focusOnLoad: Bool? = nil,
        placeholder: TextObject? = nil,
        timezone: String? = nil,
    ) {
        type = "timepicker"
        self.actionId = actionId
        self.initialTime = initialTime
        self.confirm = confirm
        self.focusOnLoad = focusOnLoad
        self.placeholder = placeholder
        self.timezone = timezone
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case actionId = "action_id"
        case initialTime = "initial_time"
        case confirm
        case focusOnLoad = "focus_on_load"
        case placeholder
        case timezone
    }
}
