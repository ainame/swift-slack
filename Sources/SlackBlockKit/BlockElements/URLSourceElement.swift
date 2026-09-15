import Foundation

/// A labeled source link used by a task card.
public struct URLSourceElement: Codable, Hashable, Sendable {
    public let type: String
    public let url: URL
    public let text: String

    public init(
        url: URL,
        text: String,
    ) {
        type = "url"
        self.url = url
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case text
    }
}
