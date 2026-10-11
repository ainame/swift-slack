import Foundation

public struct WorkflowButtonElement: Codable, Hashable, Sendable {
    public let type: String
    public let text: TextObject
    public let workflow: WorkflowObject
    public let actionId: String
    public let style: ButtonStyle?
    public let accessibilityLabel: String?

    public init(
        text: TextObject,
        workflow: WorkflowObject,
        actionId: String,
        style: ButtonStyle? = nil,
        accessibilityLabel: String? = nil,
    ) {
        type = "workflow_button"
        self.text = text
        self.workflow = workflow
        self.actionId = actionId
        self.style = style
        self.accessibilityLabel = accessibilityLabel
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case workflow
        case actionId = "action_id"
        case style
        case accessibilityLabel = "accessibility_label"
    }
}
