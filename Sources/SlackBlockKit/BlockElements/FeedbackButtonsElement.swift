import Foundation

public struct FeedbackButtonsElement: Codable, Hashable, Sendable {
    public let type: String
    public let positiveButton: FeedbackButtonObject
    public let negativeButton: FeedbackButtonObject
    public let actionId: String?

    public init(
        positiveButton: FeedbackButtonObject,
        negativeButton: FeedbackButtonObject,
        actionId: String? = nil,
    ) {
        type = "feedback_buttons"
        self.positiveButton = positiveButton
        self.negativeButton = negativeButton
        self.actionId = actionId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case positiveButton = "positive_button"
        case negativeButton = "negative_button"
        case actionId = "action_id"
    }
}
