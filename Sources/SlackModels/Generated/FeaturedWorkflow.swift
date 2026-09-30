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

/// - Remark: Generated from `#/components/schemas/FeaturedWorkflow`.
public struct FeaturedWorkflow: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/FeaturedWorkflow/channel_id`.
    public var channelId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/FeaturedWorkflow/triggers`.
    public var triggers: [Trigger]?
    /// Creates a new `FeaturedWorkflow`.
    ///
    /// - Parameters:
    ///   - channelId:
    ///   - triggers:
    public init(
        channelId: Swift.String? = nil,
        triggers: [Trigger]? = nil,
    ) {
        self.channelId = channelId
        self.triggers = triggers
    }

    public enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case triggers
    }
}
