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

/// - Remark: Generated from `#/components/schemas/DescriptionBlockElement`.
public struct DescriptionBlockElement: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/DescriptionBlockElement/elements`.
    public var elements: [ElementElementClass]?
    /// - Remark: Generated from `#/components/schemas/DescriptionBlockElement/type`.
    public var _type: Swift.String
    /// Creates a new `DescriptionBlockElement`.
    ///
    /// - Parameters:
    ///   - elements:
    ///   - _type:
    public init(
        elements: [ElementElementClass]? = nil,
        _type: Swift.String,
    ) {
        self.elements = elements
        self._type = _type
    }

    public enum CodingKeys: String, CodingKey {
        case elements
        case _type = "type"
    }
}
