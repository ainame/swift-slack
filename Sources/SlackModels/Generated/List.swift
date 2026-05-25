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

/// - Remark: Generated from `#/components/schemas/List`.
public struct List: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/List/access`.
    public var access: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/created`.
    public var created: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/List/display_as_bot`.
    public var displayAsBot: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/editable`.
    public var editable: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/external_type`.
    public var externalType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/file_access`.
    public var fileAccess: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/filetype`.
    public var filetype: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/has_rich_preview`.
    public var hasRichPreview: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/is_ai_suggested`.
    public var isAiSuggested: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/is_external`.
    public var isExternal: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/is_modified_by_ai`.
    public var isModifiedByAi: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/is_public`.
    public var isPublic: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/is_restricted_sharing_enabled`.
    public var isRestrictedSharingEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/is_starred`.
    public var isStarred: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/last_editor`.
    public var lastEditor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/list_csv_download_url`.
    public var listCsvDownloadUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/list_limits`.
    public var listLimits: ListLimits?
    /// - Remark: Generated from `#/components/schemas/List/list_metadata`.
    public var listMetadata: ListMetadata?
    /// - Remark: Generated from `#/components/schemas/List/mimetype`.
    public var mimetype: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/mode`.
    public var mode: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/name`.
    public var name: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/org_or_workspace_access`.
    public var orgOrWorkspaceAccess: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/permalink`.
    public var permalink: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/permalink_public`.
    public var permalinkPublic: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/pretty_type`.
    public var prettyType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/public_url_shared`.
    public var publicUrlShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/size`.
    public var size: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/List/skipped_shares`.
    public var skippedShares: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/List/teams_shared_with`.
    public var teamsSharedWith: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/List/timestamp`.
    public var timestamp: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/List/title`.
    public var title: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/updated`.
    public var updated: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/List/url_private`.
    public var urlPrivate: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/url_private_download`.
    public var urlPrivateDownload: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/user`.
    public var user: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/user_team`.
    public var userTeam: Swift.String?
    /// - Remark: Generated from `#/components/schemas/List/username`.
    public var username: Swift.String?
    /// Creates a new `List`.
    ///
    /// - Parameters:
    ///   - access:
    ///   - created:
    ///   - displayAsBot:
    ///   - editable:
    ///   - externalType:
    ///   - fileAccess:
    ///   - filetype:
    ///   - hasRichPreview:
    ///   - id:
    ///   - isAiSuggested:
    ///   - isExternal:
    ///   - isModifiedByAi:
    ///   - isPublic:
    ///   - isRestrictedSharingEnabled:
    ///   - isStarred:
    ///   - lastEditor:
    ///   - listCsvDownloadUrl:
    ///   - listLimits:
    ///   - listMetadata:
    ///   - mimetype:
    ///   - mode:
    ///   - name:
    ///   - orgOrWorkspaceAccess:
    ///   - permalink:
    ///   - permalinkPublic:
    ///   - prettyType:
    ///   - publicUrlShared:
    ///   - size:
    ///   - skippedShares:
    ///   - teamsSharedWith:
    ///   - timestamp:
    ///   - title:
    ///   - updated:
    ///   - urlPrivate:
    ///   - urlPrivateDownload:
    ///   - user:
    ///   - userTeam:
    ///   - username:
    public init(
        access: Swift.String? = nil,
        created: Swift.Int? = nil,
        displayAsBot: Swift.Bool? = nil,
        editable: Swift.Bool? = nil,
        externalType: Swift.String? = nil,
        fileAccess: Swift.String? = nil,
        filetype: Swift.String? = nil,
        hasRichPreview: Swift.Bool? = nil,
        id: Swift.String? = nil,
        isAiSuggested: Swift.Bool? = nil,
        isExternal: Swift.Bool? = nil,
        isModifiedByAi: Swift.Bool? = nil,
        isPublic: Swift.Bool? = nil,
        isRestrictedSharingEnabled: Swift.Bool? = nil,
        isStarred: Swift.Bool? = nil,
        lastEditor: Swift.String? = nil,
        listCsvDownloadUrl: Swift.String? = nil,
        listLimits: ListLimits? = nil,
        listMetadata: ListMetadata? = nil,
        mimetype: Swift.String? = nil,
        mode: Swift.String? = nil,
        name: Swift.String? = nil,
        orgOrWorkspaceAccess: Swift.String? = nil,
        permalink: Swift.String? = nil,
        permalinkPublic: Swift.String? = nil,
        prettyType: Swift.String? = nil,
        publicUrlShared: Swift.Bool? = nil,
        size: Swift.Int? = nil,
        skippedShares: Swift.Bool? = nil,
        teamsSharedWith: [Swift.String]? = nil,
        timestamp: Swift.Int? = nil,
        title: Swift.String? = nil,
        updated: Swift.Int? = nil,
        urlPrivate: Swift.String? = nil,
        urlPrivateDownload: Swift.String? = nil,
        user: Swift.String? = nil,
        userTeam: Swift.String? = nil,
        username: Swift.String? = nil,
    ) {
        self.access = access
        self.created = created
        self.displayAsBot = displayAsBot
        self.editable = editable
        self.externalType = externalType
        self.fileAccess = fileAccess
        self.filetype = filetype
        self.hasRichPreview = hasRichPreview
        self.id = id
        self.isAiSuggested = isAiSuggested
        self.isExternal = isExternal
        self.isModifiedByAi = isModifiedByAi
        self.isPublic = isPublic
        self.isRestrictedSharingEnabled = isRestrictedSharingEnabled
        self.isStarred = isStarred
        self.lastEditor = lastEditor
        self.listCsvDownloadUrl = listCsvDownloadUrl
        self.listLimits = listLimits
        self.listMetadata = listMetadata
        self.mimetype = mimetype
        self.mode = mode
        self.name = name
        self.orgOrWorkspaceAccess = orgOrWorkspaceAccess
        self.permalink = permalink
        self.permalinkPublic = permalinkPublic
        self.prettyType = prettyType
        self.publicUrlShared = publicUrlShared
        self.size = size
        self.skippedShares = skippedShares
        self.teamsSharedWith = teamsSharedWith
        self.timestamp = timestamp
        self.title = title
        self.updated = updated
        self.urlPrivate = urlPrivate
        self.urlPrivateDownload = urlPrivateDownload
        self.user = user
        self.userTeam = userTeam
        self.username = username
    }

    public enum CodingKeys: String, CodingKey {
        case access
        case created
        case displayAsBot = "display_as_bot"
        case editable
        case externalType = "external_type"
        case fileAccess = "file_access"
        case filetype
        case hasRichPreview = "has_rich_preview"
        case id
        case isAiSuggested = "is_ai_suggested"
        case isExternal = "is_external"
        case isModifiedByAi = "is_modified_by_ai"
        case isPublic = "is_public"
        case isRestrictedSharingEnabled = "is_restricted_sharing_enabled"
        case isStarred = "is_starred"
        case lastEditor = "last_editor"
        case listCsvDownloadUrl = "list_csv_download_url"
        case listLimits = "list_limits"
        case listMetadata = "list_metadata"
        case mimetype
        case mode
        case name
        case orgOrWorkspaceAccess = "org_or_workspace_access"
        case permalink
        case permalinkPublic = "permalink_public"
        case prettyType = "pretty_type"
        case publicUrlShared = "public_url_shared"
        case size
        case skippedShares = "skipped_shares"
        case teamsSharedWith = "teams_shared_with"
        case timestamp
        case title
        case updated
        case urlPrivate = "url_private"
        case urlPrivateDownload = "url_private_download"
        case user
        case userTeam = "user_team"
        case username
    }
}
