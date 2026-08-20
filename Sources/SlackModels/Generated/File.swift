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

#if canImport(SlackBlockKit)
import SlackBlockKit
#endif

/// - Remark: Generated from `#/components/schemas/File`.
public struct File: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/File/access`.
    public var access: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/alt_txt`.
    public var altTxt: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/app_id`.
    public var appId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/app_name`.
    public var appName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/app_provides_file_work_objects`.
    public var appProvidesFileWorkObjects: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/attachments`.
    public var attachments: [OpenAPIRuntime.OpenAPIValueContainer]?
    /// - Remark: Generated from `#/components/schemas/File/blocks`.
    public var blocks: [Block]?
    /// - Remark: Generated from `#/components/schemas/File/bot_id`.
    public var botId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/can_toggle_canvas_lock`.
    public var canToggleCanvasLock: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/canvas_creator_id`.
    public var canvasCreatorId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/canvas_printing_enabled`.
    public var canvasPrintingEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/canvas_readtime`.
    public var canvasReadtime: Swift.Double?
    /// - Remark: Generated from `#/components/schemas/File/canvas_template_mode`.
    public var canvasTemplateMode: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/cc`.
    public var cc: [Cc]?
    /// - Remark: Generated from `#/components/schemas/File/channel_actions_count`.
    public var channelActionsCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/channel_actions_ts`.
    public var channelActionsTs: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/channels`.
    public var channels: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/File/comments_count`.
    public var commentsCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/converted_pdf`.
    public var convertedPdf: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/created`.
    public var created: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/deanimate`.
    public var deanimate: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/deanimate_gif`.
    public var deanimateGif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/display_as_bot`.
    public var displayAsBot: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/dm_mpdm_users_with_file_access`.
    public var dmMpdmUsersWithFileAccess: [DmMpdmUsersWithFileAccess]?
    /// - Remark: Generated from `#/components/schemas/File/duration_ms`.
    public var durationMs: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/edit_link`.
    public var editLink: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/edit_timestamp`.
    public var editTimestamp: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/editable`.
    public var editable: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/editor`.
    public var editor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/editors`.
    public var editors: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/File/external_id`.
    public var externalId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/external_type`.
    public var externalType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/external_url`.
    public var externalUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/favorites`.
    public var favorites: [Favorite]?
    /// - Remark: Generated from `#/components/schemas/File/file_access`.
    public var fileAccess: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/filetype`.
    public var filetype: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/from`.
    public var from: [Cc]?
    /// - Remark: Generated from `#/components/schemas/File/groups`.
    public var groups: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/File/has_more`.
    public var hasMore: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/has_more_shares`.
    public var hasMoreShares: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/has_rich_preview`.
    public var hasRichPreview: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/headers`.
    public var headers: Headers?
    /// - Remark: Generated from `#/components/schemas/File/hls`.
    public var hls: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/hls_embed`.
    public var hlsEmbed: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/image_exif_rotation`.
    public var imageExifRotation: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/ims`.
    public var ims: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/File/initial_comment`.
    public var initialComment: InitialComment?
    /// - Remark: Generated from `#/components/schemas/File/inline_attachment_count`.
    public var inlineAttachmentCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/is_ai_suggested`.
    public var isAiSuggested: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_channel_space`.
    public var isChannelSpace: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_external`.
    public var isExternal: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_modified_by_ai`.
    public var isModifiedByAi: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_public`.
    public var isPublic: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_restricted_sharing_enabled`.
    public var isRestrictedSharingEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/is_starred`.
    public var isStarred: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/last_editor`.
    public var lastEditor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/last_read`.
    public var lastRead: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/lines`.
    public var lines: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/lines_more`.
    public var linesMore: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/linked_channel_id`.
    public var linkedChannelId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/list_csv_download_url`.
    public var listCsvDownloadUrl: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/list_limits`.
    public var listLimits: ListLimits?
    /// - Remark: Generated from `#/components/schemas/File/list_metadata`.
    public var listMetadata: ListMetadata?
    /// - Remark: Generated from `#/components/schemas/File/media_display_type`.
    public var mediaDisplayType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/media_progress`.
    public var mediaProgress: MediaProgress?
    /// - Remark: Generated from `#/components/schemas/File/mimetype`.
    public var mimetype: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/mode`.
    public var mode: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/mp4`.
    public var mp4: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/mp4_low`.
    public var mp4Low: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/name`.
    public var name: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/non_owner_editable`.
    public var nonOwnerEditable: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/num_stars`.
    public var numStars: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/org_or_workspace_access`.
    public var orgOrWorkspaceAccess: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/original_attachment_count`.
    public var originalAttachmentCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/original_h`.
    public var originalH: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/original_w`.
    public var originalW: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/permalink`.
    public var permalink: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/permalink_public`.
    public var permalinkPublic: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/pinned_to`.
    public var pinnedTo: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/File/pjpeg`.
    public var pjpeg: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/plain_text`.
    public var plainText: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/pretty_type`.
    public var prettyType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/preview`.
    public var preview: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/preview_highlight`.
    public var previewHighlight: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/preview_is_truncated`.
    public var previewIsTruncated: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/preview_plain_text`.
    public var previewPlainText: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/private_channels_with_file_access_count`.
    public var privateChannelsWithFileAccessCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/private_file_with_access_count`.
    public var privateFileWithAccessCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/public_url_shared`.
    public var publicUrlShared: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/quip_thread_id`.
    public var quipThreadId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/reactions`.
    public var reactions: [Reaction]?
    /// - Remark: Generated from `#/components/schemas/File/saved`.
    public var saved: Saved?
    /// - Remark: Generated from `#/components/schemas/File/sent_to_self`.
    public var sentToSelf: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/shares`.
    public var shares: Shares?
    /// - Remark: Generated from `#/components/schemas/File/show_badge`.
    public var showBadge: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/simplified_html`.
    public var simplifiedHtml: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/size`.
    public var size: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/skipped_shares`.
    public var skippedShares: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/source_team`.
    public var sourceTeam: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/subject`.
    public var subject: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/subtype`.
    public var subtype: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/team_pref_version_history_enabled`.
    public var teamPrefVersionHistoryEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/File/teams_shared_with`.
    public var teamsSharedWith: [OpenAPIRuntime.OpenAPIValueContainer]?
    /// - Remark: Generated from `#/components/schemas/File/template_conversion_ts`.
    public var templateConversionTs: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/template_description`.
    public var templateDescription: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/template_icon`.
    public var templateIcon: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/template_name`.
    public var templateName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/template_title`.
    public var templateTitle: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_1024`.
    public var thumb1024: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_1024_gif`.
    public var thumb1024Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_1024_h`.
    public var thumb1024H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_1024_w`.
    public var thumb1024W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_160`.
    public var thumb160: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_160_gif`.
    public var thumb160Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_160_h`.
    public var thumb160H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_160_w`.
    public var thumb160W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_360`.
    public var thumb360: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_360_gif`.
    public var thumb360Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_360_h`.
    public var thumb360H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_360_w`.
    public var thumb360W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_480`.
    public var thumb480: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_480_gif`.
    public var thumb480Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_480_h`.
    public var thumb480H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_480_w`.
    public var thumb480W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_64`.
    public var thumb64: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_64_gif`.
    public var thumb64Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_64_h`.
    public var thumb64H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_64_w`.
    public var thumb64W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_720`.
    public var thumb720: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_720_gif`.
    public var thumb720Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_720_h`.
    public var thumb720H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_720_w`.
    public var thumb720W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_80`.
    public var thumb80: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_800`.
    public var thumb800: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_800_gif`.
    public var thumb800Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_800_h`.
    public var thumb800H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_800_w`.
    public var thumb800W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_80_gif`.
    public var thumb80Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_80_h`.
    public var thumb80H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_80_w`.
    public var thumb80W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_960`.
    public var thumb960: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_960_gif`.
    public var thumb960Gif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_960_h`.
    public var thumb960H: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_960_w`.
    public var thumb960W: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_gif`.
    public var thumbGif: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_pdf`.
    public var thumbPdf: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_pdf_h`.
    public var thumbPdfH: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_pdf_w`.
    public var thumbPdfW: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_tiny`.
    public var thumbTiny: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_video`.
    public var thumbVideo: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/thumb_video_h`.
    public var thumbVideoH: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/thumb_video_w`.
    public var thumbVideoW: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/timestamp`.
    public var timestamp: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/title`.
    public var title: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/title_blocks`.
    public var titleBlocks: [Block]?
    /// - Remark: Generated from `#/components/schemas/File/to`.
    public var to: [Cc]?
    /// - Remark: Generated from `#/components/schemas/File/transcription`.
    public var transcription: Transcription?
    /// - Remark: Generated from `#/components/schemas/File/update_notification`.
    public var updateNotification: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/updated`.
    public var updated: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/File/url_private`.
    public var urlPrivate: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/url_private_download`.
    public var urlPrivateDownload: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/url_static_preview`.
    public var urlStaticPreview: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/user`.
    public var user: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/user_team`.
    public var userTeam: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/username`.
    public var username: Swift.String?
    /// - Remark: Generated from `#/components/schemas/File/vtt`.
    public var vtt: Swift.String?
    /// Creates a new `File`.
    ///
    /// - Parameters:
    ///   - access:
    ///   - altTxt:
    ///   - appId:
    ///   - appName:
    ///   - appProvidesFileWorkObjects:
    ///   - attachments:
    ///   - blocks:
    ///   - botId:
    ///   - canToggleCanvasLock:
    ///   - canvasCreatorId:
    ///   - canvasPrintingEnabled:
    ///   - canvasReadtime:
    ///   - canvasTemplateMode:
    ///   - cc:
    ///   - channelActionsCount:
    ///   - channelActionsTs:
    ///   - channels:
    ///   - commentsCount:
    ///   - convertedPdf:
    ///   - created:
    ///   - deanimate:
    ///   - deanimateGif:
    ///   - displayAsBot:
    ///   - dmMpdmUsersWithFileAccess:
    ///   - durationMs:
    ///   - editLink:
    ///   - editTimestamp:
    ///   - editable:
    ///   - editor:
    ///   - editors:
    ///   - externalId:
    ///   - externalType:
    ///   - externalUrl:
    ///   - favorites:
    ///   - fileAccess:
    ///   - filetype:
    ///   - from:
    ///   - groups:
    ///   - hasMore:
    ///   - hasMoreShares:
    ///   - hasRichPreview:
    ///   - headers:
    ///   - hls:
    ///   - hlsEmbed:
    ///   - id:
    ///   - imageExifRotation:
    ///   - ims:
    ///   - initialComment:
    ///   - inlineAttachmentCount:
    ///   - isAiSuggested:
    ///   - isChannelSpace:
    ///   - isExternal:
    ///   - isModifiedByAi:
    ///   - isPublic:
    ///   - isRestrictedSharingEnabled:
    ///   - isStarred:
    ///   - lastEditor:
    ///   - lastRead:
    ///   - lines:
    ///   - linesMore:
    ///   - linkedChannelId:
    ///   - listCsvDownloadUrl:
    ///   - listLimits:
    ///   - listMetadata:
    ///   - mediaDisplayType:
    ///   - mediaProgress:
    ///   - mimetype:
    ///   - mode:
    ///   - mp4:
    ///   - mp4Low:
    ///   - name:
    ///   - nonOwnerEditable:
    ///   - numStars:
    ///   - orgOrWorkspaceAccess:
    ///   - originalAttachmentCount:
    ///   - originalH:
    ///   - originalW:
    ///   - permalink:
    ///   - permalinkPublic:
    ///   - pinnedTo:
    ///   - pjpeg:
    ///   - plainText:
    ///   - prettyType:
    ///   - preview:
    ///   - previewHighlight:
    ///   - previewIsTruncated:
    ///   - previewPlainText:
    ///   - privateChannelsWithFileAccessCount:
    ///   - privateFileWithAccessCount:
    ///   - publicUrlShared:
    ///   - quipThreadId:
    ///   - reactions:
    ///   - saved:
    ///   - sentToSelf:
    ///   - shares:
    ///   - showBadge:
    ///   - simplifiedHtml:
    ///   - size:
    ///   - skippedShares:
    ///   - sourceTeam:
    ///   - subject:
    ///   - subtype:
    ///   - teamPrefVersionHistoryEnabled:
    ///   - teamsSharedWith:
    ///   - templateConversionTs:
    ///   - templateDescription:
    ///   - templateIcon:
    ///   - templateName:
    ///   - templateTitle:
    ///   - thumb1024:
    ///   - thumb1024Gif:
    ///   - thumb1024H:
    ///   - thumb1024W:
    ///   - thumb160:
    ///   - thumb160Gif:
    ///   - thumb160H:
    ///   - thumb160W:
    ///   - thumb360:
    ///   - thumb360Gif:
    ///   - thumb360H:
    ///   - thumb360W:
    ///   - thumb480:
    ///   - thumb480Gif:
    ///   - thumb480H:
    ///   - thumb480W:
    ///   - thumb64:
    ///   - thumb64Gif:
    ///   - thumb64H:
    ///   - thumb64W:
    ///   - thumb720:
    ///   - thumb720Gif:
    ///   - thumb720H:
    ///   - thumb720W:
    ///   - thumb80:
    ///   - thumb800:
    ///   - thumb800Gif:
    ///   - thumb800H:
    ///   - thumb800W:
    ///   - thumb80Gif:
    ///   - thumb80H:
    ///   - thumb80W:
    ///   - thumb960:
    ///   - thumb960Gif:
    ///   - thumb960H:
    ///   - thumb960W:
    ///   - thumbGif:
    ///   - thumbPdf:
    ///   - thumbPdfH:
    ///   - thumbPdfW:
    ///   - thumbTiny:
    ///   - thumbVideo:
    ///   - thumbVideoH:
    ///   - thumbVideoW:
    ///   - timestamp:
    ///   - title:
    ///   - titleBlocks:
    ///   - to:
    ///   - transcription:
    ///   - updateNotification:
    ///   - updated:
    ///   - urlPrivate:
    ///   - urlPrivateDownload:
    ///   - urlStaticPreview:
    ///   - user:
    ///   - userTeam:
    ///   - username:
    ///   - vtt:
    public init(
        access: Swift.String? = nil,
        altTxt: Swift.String? = nil,
        appId: Swift.String? = nil,
        appName: Swift.String? = nil,
        appProvidesFileWorkObjects: Swift.Bool? = nil,
        attachments: [OpenAPIRuntime.OpenAPIValueContainer]? = nil,
        blocks: [Block]? = nil,
        botId: Swift.String? = nil,
        canToggleCanvasLock: Swift.Bool? = nil,
        canvasCreatorId: Swift.String? = nil,
        canvasPrintingEnabled: Swift.Bool? = nil,
        canvasReadtime: Swift.Double? = nil,
        canvasTemplateMode: Swift.String? = nil,
        cc: [Cc]? = nil,
        channelActionsCount: Swift.Int? = nil,
        channelActionsTs: Swift.String? = nil,
        channels: [Swift.String]? = nil,
        commentsCount: Swift.Int? = nil,
        convertedPdf: Swift.String? = nil,
        created: Swift.Int? = nil,
        deanimate: Swift.String? = nil,
        deanimateGif: Swift.String? = nil,
        displayAsBot: Swift.Bool? = nil,
        dmMpdmUsersWithFileAccess: [DmMpdmUsersWithFileAccess]? = nil,
        durationMs: Swift.Int? = nil,
        editLink: Swift.String? = nil,
        editTimestamp: Swift.Int? = nil,
        editable: Swift.Bool? = nil,
        editor: Swift.String? = nil,
        editors: [Swift.String]? = nil,
        externalId: Swift.String? = nil,
        externalType: Swift.String? = nil,
        externalUrl: Swift.String? = nil,
        favorites: [Favorite]? = nil,
        fileAccess: Swift.String? = nil,
        filetype: Swift.String? = nil,
        from: [Cc]? = nil,
        groups: [Swift.String]? = nil,
        hasMore: Swift.Bool? = nil,
        hasMoreShares: Swift.Bool? = nil,
        hasRichPreview: Swift.Bool? = nil,
        headers: Headers? = nil,
        hls: Swift.String? = nil,
        hlsEmbed: Swift.String? = nil,
        id: Swift.String? = nil,
        imageExifRotation: Swift.Int? = nil,
        ims: [Swift.String]? = nil,
        initialComment: InitialComment? = nil,
        inlineAttachmentCount: Swift.Int? = nil,
        isAiSuggested: Swift.Bool? = nil,
        isChannelSpace: Swift.Bool? = nil,
        isExternal: Swift.Bool? = nil,
        isModifiedByAi: Swift.Bool? = nil,
        isPublic: Swift.Bool? = nil,
        isRestrictedSharingEnabled: Swift.Bool? = nil,
        isStarred: Swift.Bool? = nil,
        lastEditor: Swift.String? = nil,
        lastRead: Swift.Int? = nil,
        lines: Swift.Int? = nil,
        linesMore: Swift.Int? = nil,
        linkedChannelId: Swift.String? = nil,
        listCsvDownloadUrl: Swift.String? = nil,
        listLimits: ListLimits? = nil,
        listMetadata: ListMetadata? = nil,
        mediaDisplayType: Swift.String? = nil,
        mediaProgress: MediaProgress? = nil,
        mimetype: Swift.String? = nil,
        mode: Swift.String? = nil,
        mp4: Swift.String? = nil,
        mp4Low: Swift.String? = nil,
        name: Swift.String? = nil,
        nonOwnerEditable: Swift.Bool? = nil,
        numStars: Swift.Int? = nil,
        orgOrWorkspaceAccess: Swift.String? = nil,
        originalAttachmentCount: Swift.Int? = nil,
        originalH: Swift.String? = nil,
        originalW: Swift.String? = nil,
        permalink: Swift.String? = nil,
        permalinkPublic: Swift.String? = nil,
        pinnedTo: [Swift.String]? = nil,
        pjpeg: Swift.String? = nil,
        plainText: Swift.String? = nil,
        prettyType: Swift.String? = nil,
        preview: Swift.String? = nil,
        previewHighlight: Swift.String? = nil,
        previewIsTruncated: Swift.Bool? = nil,
        previewPlainText: Swift.String? = nil,
        privateChannelsWithFileAccessCount: Swift.Int? = nil,
        privateFileWithAccessCount: Swift.Int? = nil,
        publicUrlShared: Swift.Bool? = nil,
        quipThreadId: Swift.String? = nil,
        reactions: [Reaction]? = nil,
        saved: Saved? = nil,
        sentToSelf: Swift.Bool? = nil,
        shares: Shares? = nil,
        showBadge: Swift.Bool? = nil,
        simplifiedHtml: Swift.String? = nil,
        size: Swift.Int? = nil,
        skippedShares: Swift.Bool? = nil,
        sourceTeam: Swift.String? = nil,
        subject: Swift.String? = nil,
        subtype: Swift.String? = nil,
        teamPrefVersionHistoryEnabled: Swift.Bool? = nil,
        teamsSharedWith: [OpenAPIRuntime.OpenAPIValueContainer]? = nil,
        templateConversionTs: Swift.Int? = nil,
        templateDescription: Swift.String? = nil,
        templateIcon: Swift.String? = nil,
        templateName: Swift.String? = nil,
        templateTitle: Swift.String? = nil,
        thumb1024: Swift.String? = nil,
        thumb1024Gif: Swift.String? = nil,
        thumb1024H: Swift.String? = nil,
        thumb1024W: Swift.String? = nil,
        thumb160: Swift.String? = nil,
        thumb160Gif: Swift.String? = nil,
        thumb160H: Swift.String? = nil,
        thumb160W: Swift.String? = nil,
        thumb360: Swift.String? = nil,
        thumb360Gif: Swift.String? = nil,
        thumb360H: Swift.String? = nil,
        thumb360W: Swift.String? = nil,
        thumb480: Swift.String? = nil,
        thumb480Gif: Swift.String? = nil,
        thumb480H: Swift.String? = nil,
        thumb480W: Swift.String? = nil,
        thumb64: Swift.String? = nil,
        thumb64Gif: Swift.String? = nil,
        thumb64H: Swift.String? = nil,
        thumb64W: Swift.String? = nil,
        thumb720: Swift.String? = nil,
        thumb720Gif: Swift.String? = nil,
        thumb720H: Swift.String? = nil,
        thumb720W: Swift.String? = nil,
        thumb80: Swift.String? = nil,
        thumb800: Swift.String? = nil,
        thumb800Gif: Swift.String? = nil,
        thumb800H: Swift.String? = nil,
        thumb800W: Swift.String? = nil,
        thumb80Gif: Swift.String? = nil,
        thumb80H: Swift.String? = nil,
        thumb80W: Swift.String? = nil,
        thumb960: Swift.String? = nil,
        thumb960Gif: Swift.String? = nil,
        thumb960H: Swift.String? = nil,
        thumb960W: Swift.String? = nil,
        thumbGif: Swift.String? = nil,
        thumbPdf: Swift.String? = nil,
        thumbPdfH: Swift.String? = nil,
        thumbPdfW: Swift.String? = nil,
        thumbTiny: Swift.String? = nil,
        thumbVideo: Swift.String? = nil,
        thumbVideoH: Swift.Int? = nil,
        thumbVideoW: Swift.Int? = nil,
        timestamp: Swift.Int? = nil,
        title: Swift.String? = nil,
        titleBlocks: [Block]? = nil,
        to: [Cc]? = nil,
        transcription: Transcription? = nil,
        updateNotification: Swift.Int? = nil,
        updated: Swift.Int? = nil,
        urlPrivate: Swift.String? = nil,
        urlPrivateDownload: Swift.String? = nil,
        urlStaticPreview: Swift.String? = nil,
        user: Swift.String? = nil,
        userTeam: Swift.String? = nil,
        username: Swift.String? = nil,
        vtt: Swift.String? = nil,
    ) {
        self.access = access
        self.altTxt = altTxt
        self.appId = appId
        self.appName = appName
        self.appProvidesFileWorkObjects = appProvidesFileWorkObjects
        self.attachments = attachments
        self.blocks = blocks
        self.botId = botId
        self.canToggleCanvasLock = canToggleCanvasLock
        self.canvasCreatorId = canvasCreatorId
        self.canvasPrintingEnabled = canvasPrintingEnabled
        self.canvasReadtime = canvasReadtime
        self.canvasTemplateMode = canvasTemplateMode
        self.cc = cc
        self.channelActionsCount = channelActionsCount
        self.channelActionsTs = channelActionsTs
        self.channels = channels
        self.commentsCount = commentsCount
        self.convertedPdf = convertedPdf
        self.created = created
        self.deanimate = deanimate
        self.deanimateGif = deanimateGif
        self.displayAsBot = displayAsBot
        self.dmMpdmUsersWithFileAccess = dmMpdmUsersWithFileAccess
        self.durationMs = durationMs
        self.editLink = editLink
        self.editTimestamp = editTimestamp
        self.editable = editable
        self.editor = editor
        self.editors = editors
        self.externalId = externalId
        self.externalType = externalType
        self.externalUrl = externalUrl
        self.favorites = favorites
        self.fileAccess = fileAccess
        self.filetype = filetype
        self.from = from
        self.groups = groups
        self.hasMore = hasMore
        self.hasMoreShares = hasMoreShares
        self.hasRichPreview = hasRichPreview
        self.headers = headers
        self.hls = hls
        self.hlsEmbed = hlsEmbed
        self.id = id
        self.imageExifRotation = imageExifRotation
        self.ims = ims
        self.initialComment = initialComment
        self.inlineAttachmentCount = inlineAttachmentCount
        self.isAiSuggested = isAiSuggested
        self.isChannelSpace = isChannelSpace
        self.isExternal = isExternal
        self.isModifiedByAi = isModifiedByAi
        self.isPublic = isPublic
        self.isRestrictedSharingEnabled = isRestrictedSharingEnabled
        self.isStarred = isStarred
        self.lastEditor = lastEditor
        self.lastRead = lastRead
        self.lines = lines
        self.linesMore = linesMore
        self.linkedChannelId = linkedChannelId
        self.listCsvDownloadUrl = listCsvDownloadUrl
        self.listLimits = listLimits
        self.listMetadata = listMetadata
        self.mediaDisplayType = mediaDisplayType
        self.mediaProgress = mediaProgress
        self.mimetype = mimetype
        self.mode = mode
        self.mp4 = mp4
        self.mp4Low = mp4Low
        self.name = name
        self.nonOwnerEditable = nonOwnerEditable
        self.numStars = numStars
        self.orgOrWorkspaceAccess = orgOrWorkspaceAccess
        self.originalAttachmentCount = originalAttachmentCount
        self.originalH = originalH
        self.originalW = originalW
        self.permalink = permalink
        self.permalinkPublic = permalinkPublic
        self.pinnedTo = pinnedTo
        self.pjpeg = pjpeg
        self.plainText = plainText
        self.prettyType = prettyType
        self.preview = preview
        self.previewHighlight = previewHighlight
        self.previewIsTruncated = previewIsTruncated
        self.previewPlainText = previewPlainText
        self.privateChannelsWithFileAccessCount = privateChannelsWithFileAccessCount
        self.privateFileWithAccessCount = privateFileWithAccessCount
        self.publicUrlShared = publicUrlShared
        self.quipThreadId = quipThreadId
        self.reactions = reactions
        self.saved = saved
        self.sentToSelf = sentToSelf
        self.shares = shares
        self.showBadge = showBadge
        self.simplifiedHtml = simplifiedHtml
        self.size = size
        self.skippedShares = skippedShares
        self.sourceTeam = sourceTeam
        self.subject = subject
        self.subtype = subtype
        self.teamPrefVersionHistoryEnabled = teamPrefVersionHistoryEnabled
        self.teamsSharedWith = teamsSharedWith
        self.templateConversionTs = templateConversionTs
        self.templateDescription = templateDescription
        self.templateIcon = templateIcon
        self.templateName = templateName
        self.templateTitle = templateTitle
        self.thumb1024 = thumb1024
        self.thumb1024Gif = thumb1024Gif
        self.thumb1024H = thumb1024H
        self.thumb1024W = thumb1024W
        self.thumb160 = thumb160
        self.thumb160Gif = thumb160Gif
        self.thumb160H = thumb160H
        self.thumb160W = thumb160W
        self.thumb360 = thumb360
        self.thumb360Gif = thumb360Gif
        self.thumb360H = thumb360H
        self.thumb360W = thumb360W
        self.thumb480 = thumb480
        self.thumb480Gif = thumb480Gif
        self.thumb480H = thumb480H
        self.thumb480W = thumb480W
        self.thumb64 = thumb64
        self.thumb64Gif = thumb64Gif
        self.thumb64H = thumb64H
        self.thumb64W = thumb64W
        self.thumb720 = thumb720
        self.thumb720Gif = thumb720Gif
        self.thumb720H = thumb720H
        self.thumb720W = thumb720W
        self.thumb80 = thumb80
        self.thumb800 = thumb800
        self.thumb800Gif = thumb800Gif
        self.thumb800H = thumb800H
        self.thumb800W = thumb800W
        self.thumb80Gif = thumb80Gif
        self.thumb80H = thumb80H
        self.thumb80W = thumb80W
        self.thumb960 = thumb960
        self.thumb960Gif = thumb960Gif
        self.thumb960H = thumb960H
        self.thumb960W = thumb960W
        self.thumbGif = thumbGif
        self.thumbPdf = thumbPdf
        self.thumbPdfH = thumbPdfH
        self.thumbPdfW = thumbPdfW
        self.thumbTiny = thumbTiny
        self.thumbVideo = thumbVideo
        self.thumbVideoH = thumbVideoH
        self.thumbVideoW = thumbVideoW
        self.timestamp = timestamp
        self.title = title
        self.titleBlocks = titleBlocks
        self.to = to
        self.transcription = transcription
        self.updateNotification = updateNotification
        self.updated = updated
        self.urlPrivate = urlPrivate
        self.urlPrivateDownload = urlPrivateDownload
        self.urlStaticPreview = urlStaticPreview
        self.user = user
        self.userTeam = userTeam
        self.username = username
        self.vtt = vtt
    }

    public enum CodingKeys: String, CodingKey {
        case access
        case altTxt = "alt_txt"
        case appId = "app_id"
        case appName = "app_name"
        case appProvidesFileWorkObjects = "app_provides_file_work_objects"
        case attachments
        case blocks
        case botId = "bot_id"
        case canToggleCanvasLock = "can_toggle_canvas_lock"
        case canvasCreatorId = "canvas_creator_id"
        case canvasPrintingEnabled = "canvas_printing_enabled"
        case canvasReadtime = "canvas_readtime"
        case canvasTemplateMode = "canvas_template_mode"
        case cc
        case channelActionsCount = "channel_actions_count"
        case channelActionsTs = "channel_actions_ts"
        case channels
        case commentsCount = "comments_count"
        case convertedPdf = "converted_pdf"
        case created
        case deanimate
        case deanimateGif = "deanimate_gif"
        case displayAsBot = "display_as_bot"
        case dmMpdmUsersWithFileAccess = "dm_mpdm_users_with_file_access"
        case durationMs = "duration_ms"
        case editLink = "edit_link"
        case editTimestamp = "edit_timestamp"
        case editable
        case editor
        case editors
        case externalId = "external_id"
        case externalType = "external_type"
        case externalUrl = "external_url"
        case favorites
        case fileAccess = "file_access"
        case filetype
        case from
        case groups
        case hasMore = "has_more"
        case hasMoreShares = "has_more_shares"
        case hasRichPreview = "has_rich_preview"
        case headers
        case hls
        case hlsEmbed = "hls_embed"
        case id
        case imageExifRotation = "image_exif_rotation"
        case ims
        case initialComment = "initial_comment"
        case inlineAttachmentCount = "inline_attachment_count"
        case isAiSuggested = "is_ai_suggested"
        case isChannelSpace = "is_channel_space"
        case isExternal = "is_external"
        case isModifiedByAi = "is_modified_by_ai"
        case isPublic = "is_public"
        case isRestrictedSharingEnabled = "is_restricted_sharing_enabled"
        case isStarred = "is_starred"
        case lastEditor = "last_editor"
        case lastRead = "last_read"
        case lines
        case linesMore = "lines_more"
        case linkedChannelId = "linked_channel_id"
        case listCsvDownloadUrl = "list_csv_download_url"
        case listLimits = "list_limits"
        case listMetadata = "list_metadata"
        case mediaDisplayType = "media_display_type"
        case mediaProgress = "media_progress"
        case mimetype
        case mode
        case mp4
        case mp4Low = "mp4_low"
        case name
        case nonOwnerEditable = "non_owner_editable"
        case numStars = "num_stars"
        case orgOrWorkspaceAccess = "org_or_workspace_access"
        case originalAttachmentCount = "original_attachment_count"
        case originalH = "original_h"
        case originalW = "original_w"
        case permalink
        case permalinkPublic = "permalink_public"
        case pinnedTo = "pinned_to"
        case pjpeg
        case plainText = "plain_text"
        case prettyType = "pretty_type"
        case preview
        case previewHighlight = "preview_highlight"
        case previewIsTruncated = "preview_is_truncated"
        case previewPlainText = "preview_plain_text"
        case privateChannelsWithFileAccessCount = "private_channels_with_file_access_count"
        case privateFileWithAccessCount = "private_file_with_access_count"
        case publicUrlShared = "public_url_shared"
        case quipThreadId = "quip_thread_id"
        case reactions
        case saved
        case sentToSelf = "sent_to_self"
        case shares
        case showBadge = "show_badge"
        case simplifiedHtml = "simplified_html"
        case size
        case skippedShares = "skipped_shares"
        case sourceTeam = "source_team"
        case subject
        case subtype
        case teamPrefVersionHistoryEnabled = "team_pref_version_history_enabled"
        case teamsSharedWith = "teams_shared_with"
        case templateConversionTs = "template_conversion_ts"
        case templateDescription = "template_description"
        case templateIcon = "template_icon"
        case templateName = "template_name"
        case templateTitle = "template_title"
        case thumb1024 = "thumb_1024"
        case thumb1024Gif = "thumb_1024_gif"
        case thumb1024H = "thumb_1024_h"
        case thumb1024W = "thumb_1024_w"
        case thumb160 = "thumb_160"
        case thumb160Gif = "thumb_160_gif"
        case thumb160H = "thumb_160_h"
        case thumb160W = "thumb_160_w"
        case thumb360 = "thumb_360"
        case thumb360Gif = "thumb_360_gif"
        case thumb360H = "thumb_360_h"
        case thumb360W = "thumb_360_w"
        case thumb480 = "thumb_480"
        case thumb480Gif = "thumb_480_gif"
        case thumb480H = "thumb_480_h"
        case thumb480W = "thumb_480_w"
        case thumb64 = "thumb_64"
        case thumb64Gif = "thumb_64_gif"
        case thumb64H = "thumb_64_h"
        case thumb64W = "thumb_64_w"
        case thumb720 = "thumb_720"
        case thumb720Gif = "thumb_720_gif"
        case thumb720H = "thumb_720_h"
        case thumb720W = "thumb_720_w"
        case thumb80 = "thumb_80"
        case thumb800 = "thumb_800"
        case thumb800Gif = "thumb_800_gif"
        case thumb800H = "thumb_800_h"
        case thumb800W = "thumb_800_w"
        case thumb80Gif = "thumb_80_gif"
        case thumb80H = "thumb_80_h"
        case thumb80W = "thumb_80_w"
        case thumb960 = "thumb_960"
        case thumb960Gif = "thumb_960_gif"
        case thumb960H = "thumb_960_h"
        case thumb960W = "thumb_960_w"
        case thumbGif = "thumb_gif"
        case thumbPdf = "thumb_pdf"
        case thumbPdfH = "thumb_pdf_h"
        case thumbPdfW = "thumb_pdf_w"
        case thumbTiny = "thumb_tiny"
        case thumbVideo = "thumb_video"
        case thumbVideoH = "thumb_video_h"
        case thumbVideoW = "thumb_video_w"
        case timestamp
        case title
        case titleBlocks = "title_blocks"
        case to
        case transcription
        case updateNotification = "update_notification"
        case updated
        case urlPrivate = "url_private"
        case urlPrivateDownload = "url_private_download"
        case urlStaticPreview = "url_static_preview"
        case user
        case userTeam = "user_team"
        case username
        case vtt
    }
}
