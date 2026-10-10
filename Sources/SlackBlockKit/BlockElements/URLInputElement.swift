import Foundation

public struct URLInputElement: Codable, Hashable, Sendable {
    public let type: String
    public let actionId: String?
    public let initialValue: String?
    public let dispatchActionConfig: DispatchActionConfigurationObject?
    public let focusOnLoad: Bool?
    public let placeholder: TextObject?

    public init(
        actionId: String? = nil,
        initialValue: String? = nil,
        dispatchActionConfig: DispatchActionConfigurationObject? = nil,
        focusOnLoad: Bool? = nil,
        placeholder: TextObject? = nil,
    ) {
        type = "url_text_input"
        self.actionId = actionId
        self.initialValue = initialValue
        self.dispatchActionConfig = dispatchActionConfig
        self.focusOnLoad = focusOnLoad
        self.placeholder = placeholder
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case actionId = "action_id"
        case initialValue = "initial_value"
        case dispatchActionConfig = "dispatch_action_config"
        case focusOnLoad = "focus_on_load"
        case placeholder
    }
}
