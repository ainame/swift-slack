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

/// - Remark: Generated from `#/components/schemas/ResponseMetadata`.
public struct ResponseMetadata: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/ResponseMetadata/messages`.
    public var messages: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/ResponseMetadata/next_cursor`.
    public var nextCursor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/ResponseMetadata/warnings`.
    public var warnings: [Swift.String]?
    /// Creates a new `ResponseMetadata`.
    ///
    /// - Parameters:
    ///   - messages:
    ///   - nextCursor:
    ///   - warnings:
    public init(
        messages: [Swift.String]? = nil,
        nextCursor: Swift.String? = nil,
        warnings: [Swift.String]? = nil,
    ) {
        self.messages = messages
        self.nextCursor = nextCursor
        self.warnings = warnings
    }

    public enum CodingKeys: String, CodingKey {
        case messages
        case nextCursor = "next_cursor"
        case warnings
    }
}
