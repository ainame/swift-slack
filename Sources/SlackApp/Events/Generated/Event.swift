#if Events
import Foundation

/// Polymorphic event type that can decode any Slack event based on the type field
public enum Event: Decodable, Hashable, Sendable {
    case appHomeOpened(AppHomeOpenedEvent)
    case appMention(AppMentionEvent)
    case appRateLimited(AppRateLimitedEvent)
    case appRequested(AppRequestedEvent)
    case appUninstalled(AppUninstalledEvent)
    case callRejected(CallRejectedEvent)
    case channelArchive(ChannelArchiveEvent)
    case channelCreated(ChannelCreatedEvent)
    case channelDeleted(ChannelDeletedEvent)
    case channelHistoryChanged(ChannelHistoryChangedEvent)
    case channelIdChanged(ChannelIDChangedEvent)
    case channelLeft(ChannelLeftEvent)
    case channelRename(ChannelRenameEvent)
    case channelShared(ChannelSharedEvent)
    case channelUnarchive(ChannelUnarchiveEvent)
    case channelUnshared(ChannelUnsharedEvent)
    case dndUpdated(DndUpdatedEvent)
    case dndUpdatedUser(DndUpdatedUserEvent)
    case emailDomainChanged(EmailDomainChangedEvent)
    case emojiChanged(EmojiChangedEvent)
    case fileChange(FileChangeEvent)
    case fileCreated(FileCreatedEvent)
    case fileDeleted(FileDeletedEvent)
    case filePublic(FilePublicEvent)
    case fileShared(FileSharedEvent)
    case fileUnshared(FileUnsharedEvent)
    case goodbye(GoodbyeEvent)
    case gridMigrationFinished(GridMigrationFinishedEvent)
    case gridMigrationStarted(GridMigrationStartedEvent)
    case groupArchive(GroupArchiveEvent)
    case groupClose(GroupCloseEvent)
    case groupDeleted(GroupDeletedEvent)
    case groupHistoryChanged(GroupHistoryChangedEvent)
    case groupLeft(GroupLeftEvent)
    case groupOpen(GroupOpenEvent)
    case groupRename(GroupRenameEvent)
    case groupUnarchive(GroupUnarchiveEvent)
    case imClose(IMCloseEvent)
    case imCreated(IMCreatedEvent)
    case imHistoryChanged(IMHistoryChangedEvent)
    case imOpen(IMOpenEvent)
    case inviteRequested(InviteRequestedEvent)
    case linkShared(LinkSharedEvent)
    case memberJoinedChannel(MemberJoinedChannelEvent)
    case memberLeftChannel(MemberLeftChannelEvent)
    case messageBot(MessageBotEvent)
    case messageChanged(MessageChangedEvent)
    case messageChannelArchive(MessageChannelArchiveEvent)
    case messageChannelJoin(MessageChannelJoinEvent)
    case messageChannelLeave(MessageChannelLeaveEvent)
    case messageChannelName(MessageChannelNameEvent)
    case messageChannelPostingPermissions(MessageChannelPostingPermissionsEvent)
    case messageChannelPurpose(MessageChannelPurposeEvent)
    case messageChannelTopic(MessageChannelTopicEvent)
    case messageChannelUnarchive(MessageChannelUnarchiveEvent)
    case messageDeleted(MessageDeletedEvent)
    case messageEkmAccessDenied(MessageEkmAccessDeniedEvent)
    case message(MessageEvent)
    case messageFileShare(MessageFileShareEvent)
    case messageGroupTopic(MessageGroupTopicEvent)
    case messageMe(MessageMeEvent)
    case messageReplied(MessageRepliedEvent)
    case messageThreadBroadcast(MessageThreadBroadcastEvent)
    case pinAdded(PinAddedEvent)
    case pinRemoved(PinRemovedEvent)
    case reactionAdded(ReactionAddedEvent)
    case reactionRemoved(ReactionRemovedEvent)
    case scopeDenied(ScopeDeniedEvent)
    case scopeGranted(ScopeGrantedEvent)
    case starAdded(StarAddedEvent)
    case starRemoved(StarRemovedEvent)
    case subteamCreated(SubteamCreatedEvent)
    case subteamMembersChanged(SubteamMembersChangedEvent)
    case subteamSelfAdded(SubteamSelfAddedEvent)
    case subteamSelfRemoved(SubteamSelfRemovedEvent)
    case subteamUpdated(SubteamUpdatedEvent)
    case teamAccessGranted(TeamAccessGrantedEvent)
    case teamAccessRevoked(TeamAccessRevokedEvent)
    case teamDomainChange(TeamDomainChangeEvent)
    case teamJoin(TeamJoinEvent)
    case teamRename(TeamRenameEvent)
    case tokensRevoked(TokensRevokedEvent)
    case userChange(UserChangeEvent)
    case userHuddleChanged(UserHuddleChangedEvent)
    case userProfileChanged(UserProfileChangedEvent)
    case userStatusChanged(UserStatusChangedEvent)
    case workflowDeleted(WorkflowDeletedEvent)
    case workflowPublished(WorkflowPublishedEvent)
    case workflowStepDeleted(WorkflowStepDeletedEvent)
    case workflowStepExecute(WorkflowStepExecuteEvent)
    case workflowUnpublished(WorkflowUnpublishedEvent)
    case unsupported(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "app_home_opened":
            self = try .appHomeOpened(AppHomeOpenedEvent(from: decoder))
        case "app_mention":
            self = try .appMention(AppMentionEvent(from: decoder))
        case "app_rate_limited":
            self = try .appRateLimited(AppRateLimitedEvent(from: decoder))
        case "app_requested":
            self = try .appRequested(AppRequestedEvent(from: decoder))
        case "app_uninstalled":
            self = try .appUninstalled(AppUninstalledEvent(from: decoder))
        case "call_rejected":
            self = try .callRejected(CallRejectedEvent(from: decoder))
        case "channel_archive":
            self = try .channelArchive(ChannelArchiveEvent(from: decoder))
        case "channel_created":
            self = try .channelCreated(ChannelCreatedEvent(from: decoder))
        case "channel_deleted":
            self = try .channelDeleted(ChannelDeletedEvent(from: decoder))
        case "channel_history_changed":
            self = try .channelHistoryChanged(ChannelHistoryChangedEvent(from: decoder))
        case "channel_id_changed":
            self = try .channelIdChanged(ChannelIDChangedEvent(from: decoder))
        case "channel_left":
            self = try .channelLeft(ChannelLeftEvent(from: decoder))
        case "channel_rename":
            self = try .channelRename(ChannelRenameEvent(from: decoder))
        case "channel_shared":
            self = try .channelShared(ChannelSharedEvent(from: decoder))
        case "channel_unarchive":
            self = try .channelUnarchive(ChannelUnarchiveEvent(from: decoder))
        case "channel_unshared":
            self = try .channelUnshared(ChannelUnsharedEvent(from: decoder))
        case "dnd_updated":
            self = try .dndUpdated(DndUpdatedEvent(from: decoder))
        case "dnd_updated_user":
            self = try .dndUpdatedUser(DndUpdatedUserEvent(from: decoder))
        case "email_domain_changed":
            self = try .emailDomainChanged(EmailDomainChangedEvent(from: decoder))
        case "emoji_changed":
            self = try .emojiChanged(EmojiChangedEvent(from: decoder))
        case "file_change":
            self = try .fileChange(FileChangeEvent(from: decoder))
        case "file_created":
            self = try .fileCreated(FileCreatedEvent(from: decoder))
        case "file_deleted":
            self = try .fileDeleted(FileDeletedEvent(from: decoder))
        case "file_public":
            self = try .filePublic(FilePublicEvent(from: decoder))
        case "file_shared":
            self = try .fileShared(FileSharedEvent(from: decoder))
        case "file_unshared":
            self = try .fileUnshared(FileUnsharedEvent(from: decoder))
        case "goodbye":
            self = try .goodbye(GoodbyeEvent(from: decoder))
        case "grid_migration_finished":
            self = try .gridMigrationFinished(GridMigrationFinishedEvent(from: decoder))
        case "grid_migration_started":
            self = try .gridMigrationStarted(GridMigrationStartedEvent(from: decoder))
        case "group_archive":
            self = try .groupArchive(GroupArchiveEvent(from: decoder))
        case "group_close":
            self = try .groupClose(GroupCloseEvent(from: decoder))
        case "group_deleted":
            self = try .groupDeleted(GroupDeletedEvent(from: decoder))
        case "group_history_changed":
            self = try .groupHistoryChanged(GroupHistoryChangedEvent(from: decoder))
        case "group_left":
            self = try .groupLeft(GroupLeftEvent(from: decoder))
        case "group_open":
            self = try .groupOpen(GroupOpenEvent(from: decoder))
        case "group_rename":
            self = try .groupRename(GroupRenameEvent(from: decoder))
        case "group_unarchive":
            self = try .groupUnarchive(GroupUnarchiveEvent(from: decoder))
        case "im_close":
            self = try .imClose(IMCloseEvent(from: decoder))
        case "im_created":
            self = try .imCreated(IMCreatedEvent(from: decoder))
        case "im_history_changed":
            self = try .imHistoryChanged(IMHistoryChangedEvent(from: decoder))
        case "im_open":
            self = try .imOpen(IMOpenEvent(from: decoder))
        case "invite_requested":
            self = try .inviteRequested(InviteRequestedEvent(from: decoder))
        case "link_shared":
            self = try .linkShared(LinkSharedEvent(from: decoder))
        case "member_joined_channel":
            self = try .memberJoinedChannel(MemberJoinedChannelEvent(from: decoder))
        case "member_left_channel":
            self = try .memberLeftChannel(MemberLeftChannelEvent(from: decoder))
        case "message":
            let subtype = try decoder.container(keyedBy: SubtypeCodingKeys.self)
                .decodeIfPresent(String.self, forKey: .subtype)
            switch subtype {
            case "bot_message":
                self = try .messageBot(MessageBotEvent(from: decoder))
            case "channel_archive":
                self = try .messageChannelArchive(MessageChannelArchiveEvent(from: decoder))
            case "channel_join":
                self = try .messageChannelJoin(MessageChannelJoinEvent(from: decoder))
            case "channel_leave":
                self = try .messageChannelLeave(MessageChannelLeaveEvent(from: decoder))
            case "channel_name":
                self = try .messageChannelName(MessageChannelNameEvent(from: decoder))
            case "channel_posting_permissions":
                self = try .messageChannelPostingPermissions(MessageChannelPostingPermissionsEvent(from: decoder))
            case "channel_purpose":
                self = try .messageChannelPurpose(MessageChannelPurposeEvent(from: decoder))
            case "channel_topic":
                self = try .messageChannelTopic(MessageChannelTopicEvent(from: decoder))
            case "channel_unarchive":
                self = try .messageChannelUnarchive(MessageChannelUnarchiveEvent(from: decoder))
            case "ekm_access_denied":
                self = try .messageEkmAccessDenied(MessageEkmAccessDeniedEvent(from: decoder))
            case "file_share":
                self = try .messageFileShare(MessageFileShareEvent(from: decoder))
            case "group_topic":
                self = try .messageGroupTopic(MessageGroupTopicEvent(from: decoder))
            case "me_message":
                self = try .messageMe(MessageMeEvent(from: decoder))
            case "message_changed":
                self = try .messageChanged(MessageChangedEvent(from: decoder))
            case "message_deleted":
                self = try .messageDeleted(MessageDeletedEvent(from: decoder))
            case "message_replied":
                self = try .messageReplied(MessageRepliedEvent(from: decoder))
            case "thread_broadcast":
                self = try .messageThreadBroadcast(MessageThreadBroadcastEvent(from: decoder))
            case nil:
                self = try .message(MessageEvent(from: decoder))
            case let .some(unknownSubtype):
                self = .unsupported("message - \(unknownSubtype)")
            }
        case "pin_added":
            self = try .pinAdded(PinAddedEvent(from: decoder))
        case "pin_removed":
            self = try .pinRemoved(PinRemovedEvent(from: decoder))
        case "reaction_added":
            self = try .reactionAdded(ReactionAddedEvent(from: decoder))
        case "reaction_removed":
            self = try .reactionRemoved(ReactionRemovedEvent(from: decoder))
        case "scope_denied":
            self = try .scopeDenied(ScopeDeniedEvent(from: decoder))
        case "scope_granted":
            self = try .scopeGranted(ScopeGrantedEvent(from: decoder))
        case "star_added":
            self = try .starAdded(StarAddedEvent(from: decoder))
        case "star_removed":
            self = try .starRemoved(StarRemovedEvent(from: decoder))
        case "subteam_created":
            self = try .subteamCreated(SubteamCreatedEvent(from: decoder))
        case "subteam_members_changed":
            self = try .subteamMembersChanged(SubteamMembersChangedEvent(from: decoder))
        case "subteam_self_added":
            self = try .subteamSelfAdded(SubteamSelfAddedEvent(from: decoder))
        case "subteam_self_removed":
            self = try .subteamSelfRemoved(SubteamSelfRemovedEvent(from: decoder))
        case "subteam_updated":
            self = try .subteamUpdated(SubteamUpdatedEvent(from: decoder))
        case "team_access_granted":
            self = try .teamAccessGranted(TeamAccessGrantedEvent(from: decoder))
        case "team_access_revoked":
            self = try .teamAccessRevoked(TeamAccessRevokedEvent(from: decoder))
        case "team_domain_change":
            self = try .teamDomainChange(TeamDomainChangeEvent(from: decoder))
        case "team_join":
            self = try .teamJoin(TeamJoinEvent(from: decoder))
        case "team_rename":
            self = try .teamRename(TeamRenameEvent(from: decoder))
        case "tokens_revoked":
            self = try .tokensRevoked(TokensRevokedEvent(from: decoder))
        case "user_change":
            self = try .userChange(UserChangeEvent(from: decoder))
        case "user_huddle_changed":
            self = try .userHuddleChanged(UserHuddleChangedEvent(from: decoder))
        case "user_profile_changed":
            self = try .userProfileChanged(UserProfileChangedEvent(from: decoder))
        case "user_status_changed":
            self = try .userStatusChanged(UserStatusChangedEvent(from: decoder))
        case "workflow_deleted":
            self = try .workflowDeleted(WorkflowDeletedEvent(from: decoder))
        case "workflow_published":
            self = try .workflowPublished(WorkflowPublishedEvent(from: decoder))
        case "workflow_step_deleted":
            self = try .workflowStepDeleted(WorkflowStepDeletedEvent(from: decoder))
        case "workflow_step_execute":
            self = try .workflowStepExecute(WorkflowStepExecuteEvent(from: decoder))
        case "workflow_unpublished":
            self = try .workflowUnpublished(WorkflowUnpublishedEvent(from: decoder))
        default:
            self = .unsupported(type)
        }
    }

    /// Returns the contained event as a SlackEvent
    public var payload: (any SlackEvent)? {
        switch self {
        case let .appHomeOpened(event):
            event
        case let .appMention(event):
            event
        case let .appRateLimited(event):
            event
        case let .appRequested(event):
            event
        case let .appUninstalled(event):
            event
        case let .callRejected(event):
            event
        case let .channelArchive(event):
            event
        case let .channelCreated(event):
            event
        case let .channelDeleted(event):
            event
        case let .channelHistoryChanged(event):
            event
        case let .channelIdChanged(event):
            event
        case let .channelLeft(event):
            event
        case let .channelRename(event):
            event
        case let .channelShared(event):
            event
        case let .channelUnarchive(event):
            event
        case let .channelUnshared(event):
            event
        case let .dndUpdated(event):
            event
        case let .dndUpdatedUser(event):
            event
        case let .emailDomainChanged(event):
            event
        case let .emojiChanged(event):
            event
        case let .fileChange(event):
            event
        case let .fileCreated(event):
            event
        case let .fileDeleted(event):
            event
        case let .filePublic(event):
            event
        case let .fileShared(event):
            event
        case let .fileUnshared(event):
            event
        case let .goodbye(event):
            event
        case let .gridMigrationFinished(event):
            event
        case let .gridMigrationStarted(event):
            event
        case let .groupArchive(event):
            event
        case let .groupClose(event):
            event
        case let .groupDeleted(event):
            event
        case let .groupHistoryChanged(event):
            event
        case let .groupLeft(event):
            event
        case let .groupOpen(event):
            event
        case let .groupRename(event):
            event
        case let .groupUnarchive(event):
            event
        case let .imClose(event):
            event
        case let .imCreated(event):
            event
        case let .imHistoryChanged(event):
            event
        case let .imOpen(event):
            event
        case let .inviteRequested(event):
            event
        case let .linkShared(event):
            event
        case let .memberJoinedChannel(event):
            event
        case let .memberLeftChannel(event):
            event
        case let .messageBot(event):
            event
        case let .messageChanged(event):
            event
        case let .messageChannelArchive(event):
            event
        case let .messageChannelJoin(event):
            event
        case let .messageChannelLeave(event):
            event
        case let .messageChannelName(event):
            event
        case let .messageChannelPostingPermissions(event):
            event
        case let .messageChannelPurpose(event):
            event
        case let .messageChannelTopic(event):
            event
        case let .messageChannelUnarchive(event):
            event
        case let .messageDeleted(event):
            event
        case let .messageEkmAccessDenied(event):
            event
        case let .message(event):
            event
        case let .messageFileShare(event):
            event
        case let .messageGroupTopic(event):
            event
        case let .messageMe(event):
            event
        case let .messageReplied(event):
            event
        case let .messageThreadBroadcast(event):
            event
        case let .pinAdded(event):
            event
        case let .pinRemoved(event):
            event
        case let .reactionAdded(event):
            event
        case let .reactionRemoved(event):
            event
        case let .scopeDenied(event):
            event
        case let .scopeGranted(event):
            event
        case let .starAdded(event):
            event
        case let .starRemoved(event):
            event
        case let .subteamCreated(event):
            event
        case let .subteamMembersChanged(event):
            event
        case let .subteamSelfAdded(event):
            event
        case let .subteamSelfRemoved(event):
            event
        case let .subteamUpdated(event):
            event
        case let .teamAccessGranted(event):
            event
        case let .teamAccessRevoked(event):
            event
        case let .teamDomainChange(event):
            event
        case let .teamJoin(event):
            event
        case let .teamRename(event):
            event
        case let .tokensRevoked(event):
            event
        case let .userChange(event):
            event
        case let .userHuddleChanged(event):
            event
        case let .userProfileChanged(event):
            event
        case let .userStatusChanged(event):
            event
        case let .workflowDeleted(event):
            event
        case let .workflowPublished(event):
            event
        case let .workflowStepDeleted(event):
            event
        case let .workflowStepExecute(event):
            event
        case let .workflowUnpublished(event):
            event
        case .unsupported:
            nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum SubtypeCodingKeys: String, CodingKey {
        case subtype
    }
}
#endif
