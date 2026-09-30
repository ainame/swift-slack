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

/// - Remark: Generated from `#/components/schemas/Participant`.
public struct Participant: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Participant/avatar_url`.
    public var avatarUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Participant/display_name`.
    public var displayName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Participant/external_id`.
    public var externalId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Participant/slack_id`.
    public var slackId: Swift.String?
    /// Creates a new `Participant`.
    ///
    /// - Parameters:
    ///   - avatarUrl:
    ///   - displayName:
    ///   - externalId:
    ///   - slackId:
    public init(
        avatarUrl: Swift.String? = nil,
        displayName: Swift.String? = nil,
        externalId: Swift.String? = nil,
        slackId: Swift.String? = nil,
    ) {
        self.avatarUrl = avatarUrl
        self.displayName = displayName
        self.externalId = externalId
        self.slackId = slackId
    }

    public enum CodingKeys: String, CodingKey {
        case avatarUrl = "avatar_url"
        case displayName = "display_name"
        case externalId = "external_id"
        case slackId = "slack_id"
    }
}
