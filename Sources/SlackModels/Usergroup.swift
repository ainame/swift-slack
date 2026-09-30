import Foundation

/// A user group (also called a subteam).
///
/// Mirrors `com.slack.api.model.Usergroup` in java-slack-sdk. This is hand-written because each
/// usergroups fixture contains a different subset of fields, and the generated model kept only the
/// subset of whichever fixture was merged last. The members and `CodingKeys` of the previously
/// generated model are kept for source compatibility.
public struct Usergroup: Codable, Hashable, Sendable {
    public var autoProvision: Swift.Bool?
    public var autoType: Swift.String?
    public var channelCount: Swift.Int?
    public var createdBy: Swift.String?
    public var dateCreate: Swift.Int?
    public var dateDelete: Swift.Int?
    public var dateUpdate: Swift.Int?
    public var deletedBy: Swift.String?
    public var description: Swift.String?
    public var enterpriseSubteamId: Swift.String?
    public var handle: Swift.String?
    public var id: Swift.String?
    public var isEditingRestricted: Swift.Bool?
    public var isExternal: Swift.Bool?
    public var isIdpGroup: Swift.Bool?
    public var isMembershipLocked: Swift.Bool?
    public var isOrgLevel: Swift.Bool?
    public var isSection: Swift.Bool?
    public var isSubteam: Swift.Bool?
    public var isUsergroup: Swift.Bool?
    public var isVisible: Swift.Bool?
    public var name: Swift.String?
    public var prefs: Prefs?
    public var teamId: Swift.String?
    public var updatedBy: Swift.String?
    public var userCount: Swift.Int?
    public var users: [Swift.String]?

    public init(
        autoProvision: Swift.Bool? = nil,
        autoType: Swift.String? = nil,
        channelCount: Swift.Int? = nil,
        createdBy: Swift.String? = nil,
        dateCreate: Swift.Int? = nil,
        dateDelete: Swift.Int? = nil,
        dateUpdate: Swift.Int? = nil,
        deletedBy: Swift.String? = nil,
        description: Swift.String? = nil,
        enterpriseSubteamId: Swift.String? = nil,
        handle: Swift.String? = nil,
        id: Swift.String? = nil,
        isEditingRestricted: Swift.Bool? = nil,
        isExternal: Swift.Bool? = nil,
        isIdpGroup: Swift.Bool? = nil,
        isMembershipLocked: Swift.Bool? = nil,
        isOrgLevel: Swift.Bool? = nil,
        isSection: Swift.Bool? = nil,
        isSubteam: Swift.Bool? = nil,
        isUsergroup: Swift.Bool? = nil,
        isVisible: Swift.Bool? = nil,
        name: Swift.String? = nil,
        prefs: Prefs? = nil,
        teamId: Swift.String? = nil,
        updatedBy: Swift.String? = nil,
        userCount: Swift.Int? = nil,
        users: [Swift.String]? = nil,
    ) {
        self.autoProvision = autoProvision
        self.autoType = autoType
        self.channelCount = channelCount
        self.createdBy = createdBy
        self.dateCreate = dateCreate
        self.dateDelete = dateDelete
        self.dateUpdate = dateUpdate
        self.deletedBy = deletedBy
        self.description = description
        self.enterpriseSubteamId = enterpriseSubteamId
        self.handle = handle
        self.id = id
        self.isEditingRestricted = isEditingRestricted
        self.isExternal = isExternal
        self.isIdpGroup = isIdpGroup
        self.isMembershipLocked = isMembershipLocked
        self.isOrgLevel = isOrgLevel
        self.isSection = isSection
        self.isSubteam = isSubteam
        self.isUsergroup = isUsergroup
        self.isVisible = isVisible
        self.name = name
        self.prefs = prefs
        self.teamId = teamId
        self.updatedBy = updatedBy
        self.userCount = userCount
        self.users = users
    }

    public enum CodingKeys: String, CodingKey {
        case autoProvision = "auto_provision"
        case autoType = "auto_type"
        case channelCount = "channel_count"
        case createdBy = "created_by"
        case dateCreate = "date_create"
        case dateDelete = "date_delete"
        case dateUpdate = "date_update"
        case deletedBy = "deleted_by"
        case description
        case enterpriseSubteamId = "enterprise_subteam_id"
        case handle
        case id
        case isEditingRestricted = "is_editing_restricted"
        case isExternal = "is_external"
        case isIdpGroup = "is_idp_group"
        case isMembershipLocked = "is_membership_locked"
        case isOrgLevel = "is_org_level"
        case isSection = "is_section"
        case isSubteam = "is_subteam"
        case isUsergroup = "is_usergroup"
        case isVisible = "is_visible"
        case name
        case prefs
        case teamId = "team_id"
        case updatedBy = "updated_by"
        case userCount = "user_count"
        case users
    }
}
