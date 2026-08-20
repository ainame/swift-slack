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

/// - Remark: Generated from `#/components/schemas/Trigger`.
public struct Trigger: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Trigger/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Trigger/title`.
    public var title: Swift.String?
    /// Creates a new `Trigger`.
    ///
    /// - Parameters:
    ///   - id:
    ///   - title:
    public init(
        id: Swift.String? = nil,
        title: Swift.String? = nil,
    ) {
        self.id = id
        self.title = title
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case title
    }
}
