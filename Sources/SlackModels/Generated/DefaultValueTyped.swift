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

/// - Remark: Generated from `#/components/schemas/DefaultValueTyped`.
public struct DefaultValueTyped: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/DefaultValueTyped/user`.
    public var user: [Swift.String]?
    /// Creates a new `DefaultValueTyped`.
    ///
    /// - Parameters:
    ///   - user:
    public init(user: [Swift.String]? = nil) {
        self.user = user
    }

    public enum CodingKeys: String, CodingKey {
        case user
    }
}
