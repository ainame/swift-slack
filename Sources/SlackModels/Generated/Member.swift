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

/// - Remark: Generated from `#/components/schemas/Member`.
public struct Member: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Member/color`.
    public var color: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/deleted`.
    public var deleted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/enterprise_user`.
    public var enterpriseUser: EnterpriseUser?
    /// - Remark: Generated from `#/components/schemas/Member/has_2fa`.
    public var has2fa: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/is_admin`.
    public var isAdmin: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_app_user`.
    public var isAppUser: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_bot`.
    public var isBot: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_email_confirmed`.
    public var isEmailConfirmed: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_owner`.
    public var isOwner: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_primary_owner`.
    public var isPrimaryOwner: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_restricted`.
    public var isRestricted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_ultra_restricted`.
    public var isUltraRestricted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/is_workflow_bot`.
    public var isWorkflowBot: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Member/locale`.
    public var locale: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/name`.
    public var name: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/profile`.
    public var profile: UserProfile?
    /// - Remark: Generated from `#/components/schemas/Member/real_name`.
    public var realName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/team_id`.
    public var teamId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/two_factor_type`.
    public var twoFactorType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/tz`.
    public var tz: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/tz_label`.
    public var tzLabel: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Member/tz_offset`.
    public var tzOffset: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Member/updated`.
    public var updated: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Member/who_can_share_contact_card`.
    public var whoCanShareContactCard: Swift.String?
    /// Creates a new `Member`.
    ///
    /// - Parameters:
    ///   - color:
    ///   - deleted:
    ///   - enterpriseUser:
    ///   - has2fa:
    ///   - id:
    ///   - isAdmin:
    ///   - isAppUser:
    ///   - isBot:
    ///   - isEmailConfirmed:
    ///   - isOwner:
    ///   - isPrimaryOwner:
    ///   - isRestricted:
    ///   - isUltraRestricted:
    ///   - isWorkflowBot:
    ///   - locale:
    ///   - name:
    ///   - profile:
    ///   - realName:
    ///   - teamId:
    ///   - twoFactorType:
    ///   - tz:
    ///   - tzLabel:
    ///   - tzOffset:
    ///   - updated:
    ///   - whoCanShareContactCard:
    public init(
        color: Swift.String? = nil,
        deleted: Swift.Bool? = nil,
        enterpriseUser: EnterpriseUser? = nil,
        has2fa: Swift.Bool? = nil,
        id: Swift.String? = nil,
        isAdmin: Swift.Bool? = nil,
        isAppUser: Swift.Bool? = nil,
        isBot: Swift.Bool? = nil,
        isEmailConfirmed: Swift.Bool? = nil,
        isOwner: Swift.Bool? = nil,
        isPrimaryOwner: Swift.Bool? = nil,
        isRestricted: Swift.Bool? = nil,
        isUltraRestricted: Swift.Bool? = nil,
        isWorkflowBot: Swift.Bool? = nil,
        locale: Swift.String? = nil,
        name: Swift.String? = nil,
        profile: UserProfile? = nil,
        realName: Swift.String? = nil,
        teamId: Swift.String? = nil,
        twoFactorType: Swift.String? = nil,
        tz: Swift.String? = nil,
        tzLabel: Swift.String? = nil,
        tzOffset: Swift.Int? = nil,
        updated: Swift.Int? = nil,
        whoCanShareContactCard: Swift.String? = nil,
    ) {
        self.color = color
        self.deleted = deleted
        self.enterpriseUser = enterpriseUser
        self.has2fa = has2fa
        self.id = id
        self.isAdmin = isAdmin
        self.isAppUser = isAppUser
        self.isBot = isBot
        self.isEmailConfirmed = isEmailConfirmed
        self.isOwner = isOwner
        self.isPrimaryOwner = isPrimaryOwner
        self.isRestricted = isRestricted
        self.isUltraRestricted = isUltraRestricted
        self.isWorkflowBot = isWorkflowBot
        self.locale = locale
        self.name = name
        self.profile = profile
        self.realName = realName
        self.teamId = teamId
        self.twoFactorType = twoFactorType
        self.tz = tz
        self.tzLabel = tzLabel
        self.tzOffset = tzOffset
        self.updated = updated
        self.whoCanShareContactCard = whoCanShareContactCard
    }

    public enum CodingKeys: String, CodingKey {
        case color
        case deleted
        case enterpriseUser = "enterprise_user"
        case has2fa = "has_2fa"
        case id
        case isAdmin = "is_admin"
        case isAppUser = "is_app_user"
        case isBot = "is_bot"
        case isEmailConfirmed = "is_email_confirmed"
        case isOwner = "is_owner"
        case isPrimaryOwner = "is_primary_owner"
        case isRestricted = "is_restricted"
        case isUltraRestricted = "is_ultra_restricted"
        case isWorkflowBot = "is_workflow_bot"
        case locale
        case name
        case profile
        case realName = "real_name"
        case teamId = "team_id"
        case twoFactorType = "two_factor_type"
        case tz
        case tzLabel = "tz_label"
        case tzOffset = "tz_offset"
        case updated
        case whoCanShareContactCard = "who_can_share_contact_card"
    }
}
