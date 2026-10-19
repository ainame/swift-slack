import Foundation

/// A block that displays a short alert message. Currently supported only in modals.
public struct AlertBlock: Codable, Hashable, Sendable {
    public let type: String
    public let text: TextObject
    public let level: AlertLevel?
    public let blockId: String?

    public init(text: TextObject, level: AlertLevel? = nil, blockId: String? = nil) {
        type = "alert"
        self.text = text
        self.level = level
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case level
        case blockId = "block_id"
    }
}

public enum AlertLevel: String, Codable, Hashable, Sendable {
    case `default`
    case info
    case warning
    case error
    case success
}
