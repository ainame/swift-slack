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

/// - Remark: Generated from `#/components/schemas/Call`.
public struct Call: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Call/media_backend_type`.
    public var mediaBackendType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Call/v1`.
    public var v1: V1?
    /// Creates a new `Call`.
    ///
    /// - Parameters:
    ///   - mediaBackendType:
    ///   - v1:
    public init(
        mediaBackendType: Swift.String? = nil,
        v1: V1? = nil,
    ) {
        self.mediaBackendType = mediaBackendType
        self.v1 = v1
    }

    public enum CodingKeys: String, CodingKey {
        case mediaBackendType = "media_backend_type"
        case v1
    }
}
