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

/// - Remark: Generated from `#/components/schemas/Channel`.
public struct Channel: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Channel/context_team_id`.
    public var contextTeamId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/conversation_host_id`.
    public var conversationHostId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/created`.
    public var created: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Channel/creator`.
    public var creator: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/enterprise_id`.
    public var enterpriseId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/internal_team_ids`.
    public var internalTeamIds: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Channel/is_archived`.
    public var isArchived: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_channel`.
    public var isChannel: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_ext_shared`.
    public var isExtShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_general`.
    public var isGeneral: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_global_shared`.
    public var isGlobalShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_group`.
    public var isGroup: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_im`.
    public var isIm: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_moved`.
    public var isMoved: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Channel/is_mpim`.
    public var isMpim: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_open`.
    public var isOpen: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_org_default`.
    public var isOrgDefault: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_org_mandatory`.
    public var isOrgMandatory: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_org_shared`.
    public var isOrgShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_pending_ext_shared`.
    public var isPendingExtShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_private`.
    public var isPrivate: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_shared`.
    public var isShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/is_user_deleted`.
    public var isUserDeleted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Channel/last_read`.
    public var lastRead: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/name`.
    public var name: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/name_normalized`.
    public var nameNormalized: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/parent_conversation`.
    public var parentConversation: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Channel/pending_connected_team_ids`.
    public var pendingConnectedTeamIds: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Channel/pending_shared`.
    public var pendingShared: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Channel/previous_names`.
    public var previousNames: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Channel/priority`.
    public var priority: Swift.Double?
    /// - Remark: Generated from `#/components/schemas/Channel/properties`.
    public var properties: Properties?
    /// - Remark: Generated from `#/components/schemas/Channel/purpose`.
    public var purpose: Purpose?
    /// - Remark: Generated from `#/components/schemas/Channel/shared_team_ids`.
    public var sharedTeamIds: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Channel/topic`.
    public var topic: Purpose?
    /// - Remark: Generated from `#/components/schemas/Channel/unlinked`.
    public var unlinked: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Channel/updated`.
    public var updated: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Channel/user`.
    public var user: Swift.String?
    /// Creates a new `Channel`.
    ///
    /// - Parameters:
    ///   - contextTeamId:
    ///   - conversationHostId:
    ///   - created:
    ///   - creator:
    ///   - enterpriseId:
    ///   - id:
    ///   - internalTeamIds:
    ///   - isArchived:
    ///   - isChannel:
    ///   - isExtShared:
    ///   - isGeneral:
    ///   - isGlobalShared:
    ///   - isGroup:
    ///   - isIm:
    ///   - isMoved:
    ///   - isMpim:
    ///   - isOpen:
    ///   - isOrgDefault:
    ///   - isOrgMandatory:
    ///   - isOrgShared:
    ///   - isPendingExtShared:
    ///   - isPrivate:
    ///   - isShared:
    ///   - isUserDeleted:
    ///   - lastRead:
    ///   - name:
    ///   - nameNormalized:
    ///   - parentConversation:
    ///   - pendingConnectedTeamIds:
    ///   - pendingShared:
    ///   - previousNames:
    ///   - priority:
    ///   - properties:
    ///   - purpose:
    ///   - sharedTeamIds:
    ///   - topic:
    ///   - unlinked:
    ///   - updated:
    ///   - user:
    public init(
        contextTeamId: Swift.String? = nil,
        conversationHostId: Swift.String? = nil,
        created: Swift.Int? = nil,
        creator: Swift.String? = nil,
        enterpriseId: Swift.String? = nil,
        id: Swift.String? = nil,
        internalTeamIds: [Swift.String]? = nil,
        isArchived: Swift.Bool? = nil,
        isChannel: Swift.Bool? = nil,
        isExtShared: Swift.Bool? = nil,
        isGeneral: Swift.Bool? = nil,
        isGlobalShared: Swift.Bool? = nil,
        isGroup: Swift.Bool? = nil,
        isIm: Swift.Bool? = nil,
        isMoved: Swift.Int? = nil,
        isMpim: Swift.Bool? = nil,
        isOpen: Swift.Bool? = nil,
        isOrgDefault: Swift.Bool? = nil,
        isOrgMandatory: Swift.Bool? = nil,
        isOrgShared: Swift.Bool? = nil,
        isPendingExtShared: Swift.Bool? = nil,
        isPrivate: Swift.Bool? = nil,
        isShared: Swift.Bool? = nil,
        isUserDeleted: Swift.Bool? = nil,
        lastRead: Swift.String? = nil,
        name: Swift.String? = nil,
        nameNormalized: Swift.String? = nil,
        parentConversation: Swift.String? = nil,
        pendingConnectedTeamIds: [Swift.String]? = nil,
        pendingShared: [Swift.String]? = nil,
        previousNames: [Swift.String]? = nil,
        priority: Swift.Double? = nil,
        properties: Properties? = nil,
        purpose: Purpose? = nil,
        sharedTeamIds: [Swift.String]? = nil,
        topic: Purpose? = nil,
        unlinked: Swift.Int? = nil,
        updated: Swift.Int? = nil,
        user: Swift.String? = nil,
    ) {
        self.contextTeamId = contextTeamId
        self.conversationHostId = conversationHostId
        self.created = created
        self.creator = creator
        self.enterpriseId = enterpriseId
        self.id = id
        self.internalTeamIds = internalTeamIds
        self.isArchived = isArchived
        self.isChannel = isChannel
        self.isExtShared = isExtShared
        self.isGeneral = isGeneral
        self.isGlobalShared = isGlobalShared
        self.isGroup = isGroup
        self.isIm = isIm
        self.isMoved = isMoved
        self.isMpim = isMpim
        self.isOpen = isOpen
        self.isOrgDefault = isOrgDefault
        self.isOrgMandatory = isOrgMandatory
        self.isOrgShared = isOrgShared
        self.isPendingExtShared = isPendingExtShared
        self.isPrivate = isPrivate
        self.isShared = isShared
        self.isUserDeleted = isUserDeleted
        self.lastRead = lastRead
        self.name = name
        self.nameNormalized = nameNormalized
        self.parentConversation = parentConversation
        self.pendingConnectedTeamIds = pendingConnectedTeamIds
        self.pendingShared = pendingShared
        self.previousNames = previousNames
        self.priority = priority
        self.properties = properties
        self.purpose = purpose
        self.sharedTeamIds = sharedTeamIds
        self.topic = topic
        self.unlinked = unlinked
        self.updated = updated
        self.user = user
    }

    public enum CodingKeys: String, CodingKey {
        case contextTeamId = "context_team_id"
        case conversationHostId = "conversation_host_id"
        case created
        case creator
        case enterpriseId = "enterprise_id"
        case id
        case internalTeamIds = "internal_team_ids"
        case isArchived = "is_archived"
        case isChannel = "is_channel"
        case isExtShared = "is_ext_shared"
        case isGeneral = "is_general"
        case isGlobalShared = "is_global_shared"
        case isGroup = "is_group"
        case isIm = "is_im"
        case isMoved = "is_moved"
        case isMpim = "is_mpim"
        case isOpen = "is_open"
        case isOrgDefault = "is_org_default"
        case isOrgMandatory = "is_org_mandatory"
        case isOrgShared = "is_org_shared"
        case isPendingExtShared = "is_pending_ext_shared"
        case isPrivate = "is_private"
        case isShared = "is_shared"
        case isUserDeleted = "is_user_deleted"
        case lastRead = "last_read"
        case name
        case nameNormalized = "name_normalized"
        case parentConversation = "parent_conversation"
        case pendingConnectedTeamIds = "pending_connected_team_ids"
        case pendingShared = "pending_shared"
        case previousNames = "previous_names"
        case priority
        case properties
        case purpose
        case sharedTeamIds = "shared_team_ids"
        case topic
        case unlinked
        case updated
        case user
    }
}
