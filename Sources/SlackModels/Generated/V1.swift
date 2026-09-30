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

/// - Remark: Generated from `#/components/schemas/V1`.
public struct V1: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/V1/active_participants`.
    public var activeParticipants: [Participant]?
    /// - Remark: Generated from `#/components/schemas/V1/all_participants`.
    public var allParticipants: [Participant]?
    /// - Remark: Generated from `#/components/schemas/V1/app_icon_urls`.
    public var appIconUrls: AppIconUrls?
    /// - Remark: Generated from `#/components/schemas/V1/app_id`.
    public var appId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/channels`.
    public var channels: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/V1/created_by`.
    public var createdBy: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/date_end`.
    public var dateEnd: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/V1/date_start`.
    public var dateStart: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/V1/desktop_app_join_url`.
    public var desktopAppJoinUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/display_id`.
    public var displayId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/has_ended`.
    public var hasEnded: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/V1/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/is_dm_call`.
    public var isDmCall: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/V1/join_url`.
    public var joinUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/name`.
    public var name: Swift.String?
    /// - Remark: Generated from `#/components/schemas/V1/was_accepted`.
    public var wasAccepted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/V1/was_missed`.
    public var wasMissed: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/V1/was_rejected`.
    public var wasRejected: Swift.Bool?
    /// Creates a new `V1`.
    ///
    /// - Parameters:
    ///   - activeParticipants:
    ///   - allParticipants:
    ///   - appIconUrls:
    ///   - appId:
    ///   - channels:
    ///   - createdBy:
    ///   - dateEnd:
    ///   - dateStart:
    ///   - desktopAppJoinUrl:
    ///   - displayId:
    ///   - hasEnded:
    ///   - id:
    ///   - isDmCall:
    ///   - joinUrl:
    ///   - name:
    ///   - wasAccepted:
    ///   - wasMissed:
    ///   - wasRejected:
    public init(
        activeParticipants: [Participant]? = nil,
        allParticipants: [Participant]? = nil,
        appIconUrls: AppIconUrls? = nil,
        appId: Swift.String? = nil,
        channels: [Swift.String]? = nil,
        createdBy: Swift.String? = nil,
        dateEnd: Swift.Int? = nil,
        dateStart: Swift.Int? = nil,
        desktopAppJoinUrl: Swift.String? = nil,
        displayId: Swift.String? = nil,
        hasEnded: Swift.Bool? = nil,
        id: Swift.String? = nil,
        isDmCall: Swift.Bool? = nil,
        joinUrl: Swift.String? = nil,
        name: Swift.String? = nil,
        wasAccepted: Swift.Bool? = nil,
        wasMissed: Swift.Bool? = nil,
        wasRejected: Swift.Bool? = nil,
    ) {
        self.activeParticipants = activeParticipants
        self.allParticipants = allParticipants
        self.appIconUrls = appIconUrls
        self.appId = appId
        self.channels = channels
        self.createdBy = createdBy
        self.dateEnd = dateEnd
        self.dateStart = dateStart
        self.desktopAppJoinUrl = desktopAppJoinUrl
        self.displayId = displayId
        self.hasEnded = hasEnded
        self.id = id
        self.isDmCall = isDmCall
        self.joinUrl = joinUrl
        self.name = name
        self.wasAccepted = wasAccepted
        self.wasMissed = wasMissed
        self.wasRejected = wasRejected
    }

    public enum CodingKeys: String, CodingKey {
        case activeParticipants = "active_participants"
        case allParticipants = "all_participants"
        case appIconUrls = "app_icon_urls"
        case appId = "app_id"
        case channels
        case createdBy = "created_by"
        case dateEnd = "date_end"
        case dateStart = "date_start"
        case desktopAppJoinUrl = "desktop_app_join_url"
        case displayId = "display_id"
        case hasEnded = "has_ended"
        case id
        case isDmCall = "is_dm_call"
        case joinUrl = "join_url"
        case name
        case wasAccepted = "was_accepted"
        case wasMissed = "was_missed"
        case wasRejected = "was_rejected"
    }
}
