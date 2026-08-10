@_spi(Generated) import OpenAPIRuntime
#if os(Linux)
@preconcurrency import struct Foundation.Data
@preconcurrency import struct Foundation.Date
@preconcurrency import struct Foundation.URL
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
#endif

#if canImport(SlackBlockKit)
import SlackBlockKit
#endif

/// - Remark: Generated from `#/components/schemas/DescriptionBlock`.
public struct DescriptionBlock: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/DescriptionBlock/block_id`.
    public var blockId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/DescriptionBlock/elements`.
    public var elements: [DescriptionBlockElement]?
    /// - Remark: Generated from `#/components/schemas/DescriptionBlock/type`.
    public var _type: Swift.String
    /// Creates a new `DescriptionBlock`.
    ///
    /// - Parameters:
    ///   - blockId:
    ///   - elements:
    ///   - _type:
    public init(
        blockId: Swift.String? = nil,
        elements: [DescriptionBlockElement]? = nil,
        _type: Swift.String,
    ) {
        self.blockId = blockId
        self.elements = elements
        self._type = _type
    }

    public enum CodingKeys: String, CodingKey {
        case blockId = "block_id"
        case elements
        case _type = "type"
    }
}
