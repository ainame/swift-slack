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

/// - Remark: Generated from `#/components/schemas/ElementElementClass`.
public struct ElementElementClass: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/ElementElementClass/text`.
    public var text: Swift.String?
    /// - Remark: Generated from `#/components/schemas/ElementElementClass/type`.
    public var _type: Swift.String
    /// Creates a new `ElementElementClass`.
    ///
    /// - Parameters:
    ///   - text:
    ///   - _type:
    public init(
        text: Swift.String? = nil,
        _type: Swift.String,
    ) {
        self.text = text
        self._type = _type
    }

    public enum CodingKeys: String, CodingKey {
        case text
        case _type = "type"
    }
}
