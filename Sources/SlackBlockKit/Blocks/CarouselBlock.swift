import Foundation

/// A horizontally scrollable list of 1 to 10 card blocks.
public struct CarouselBlock: Codable, Hashable, Sendable {
    public let type: String
    public let elements: [CardBlock]
    public let blockId: String?

    public init(elements: [CardBlock], blockId: String? = nil) {
        type = "carousel"
        self.elements = elements
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case elements
        case blockId = "block_id"
    }
}
