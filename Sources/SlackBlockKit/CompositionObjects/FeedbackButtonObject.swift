import Foundation

/// A positive or negative button used by ``FeedbackButtonsElement``.
public struct FeedbackButtonObject: Codable, Hashable, Sendable {
    public let text: TextObject
    public let value: String
    public let accessibilityLabel: String?

    public init(text: TextObject, value: String, accessibilityLabel: String? = nil) {
        self.text = text
        self.value = value
        self.accessibilityLabel = accessibilityLabel
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case value
        case accessibilityLabel = "accessibility_label"
    }
}
