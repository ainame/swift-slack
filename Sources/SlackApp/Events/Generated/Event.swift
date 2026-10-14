#if Events
import Foundation

/// Polymorphic event type that can decode any Slack event based on the type field
public enum Event: Decodable, Hashable, Sendable {
    case agentSessionStopped(AgentSessionStoppedEvent)
    case agentSessionTitleChanged(AgentSessionTitleChangedEvent)
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
    case codeChannelAction(CodeChannelActionEvent)
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

        // Each event decodes in its own closure. A `switch` with an arm per event would give this
        // initializer a stack frame that overflows a Swift concurrency thread in debug builds.
        if let decoders = Self.subtypeDecoders[type] {
            let subtype = try decoder.container(keyedBy: SubtypeCodingKeys.self)
                .decodeIfPresent(String.self, forKey: .subtype)
            if let decode = decoders[subtype] {
                self = try decode(decoder)
            } else if let subtype {
                self = .unsupported("\(type) - \(subtype)")
            } else {
                self = .unsupported(type)
            }
        } else if let decode = Self.decoders[type] {
            self = try decode(decoder)
        } else {
            self = .unsupported(type)
        }
    }

    private typealias Decode = @Sendable (any Decoder) throws -> Event

    /// Decoders for event types without subtypes, keyed by `type`.
    private static let decoders: [String: Decode] = [
        "agent_session_stopped": { try .agentSessionStopped(AgentSessionStoppedEvent(from: $0)) },
        "agent_session_title_changed": { try .agentSessionTitleChanged(AgentSessionTitleChangedEvent(from: $0)) },
        "app_home_opened": { try .appHomeOpened(AppHomeOpenedEvent(from: $0)) },
        "app_mention": { try .appMention(AppMentionEvent(from: $0)) },
        "app_rate_limited": { try .appRateLimited(AppRateLimitedEvent(from: $0)) },
        "app_requested": { try .appRequested(AppRequestedEvent(from: $0)) },
        "app_uninstalled": { try .appUninstalled(AppUninstalledEvent(from: $0)) },
        "call_rejected": { try .callRejected(CallRejectedEvent(from: $0)) },
        "channel_archive": { try .channelArchive(ChannelArchiveEvent(from: $0)) },
        "channel_created": { try .channelCreated(ChannelCreatedEvent(from: $0)) },
        "channel_deleted": { try .channelDeleted(ChannelDeletedEvent(from: $0)) },
        "channel_history_changed": { try .channelHistoryChanged(ChannelHistoryChangedEvent(from: $0)) },
        "channel_id_changed": { try .channelIdChanged(ChannelIDChangedEvent(from: $0)) },
        "channel_left": { try .channelLeft(ChannelLeftEvent(from: $0)) },
        "channel_rename": { try .channelRename(ChannelRenameEvent(from: $0)) },
        "channel_shared": { try .channelShared(ChannelSharedEvent(from: $0)) },
        "channel_unarchive": { try .channelUnarchive(ChannelUnarchiveEvent(from: $0)) },
        "channel_unshared": { try .channelUnshared(ChannelUnsharedEvent(from: $0)) },
        "code_channel_action": { try .codeChannelAction(CodeChannelActionEvent(from: $0)) },
        "dnd_updated": { try .dndUpdated(DndUpdatedEvent(from: $0)) },
        "dnd_updated_user": { try .dndUpdatedUser(DndUpdatedUserEvent(from: $0)) },
        "email_domain_changed": { try .emailDomainChanged(EmailDomainChangedEvent(from: $0)) },
        "emoji_changed": { try .emojiChanged(EmojiChangedEvent(from: $0)) },
        "file_change": { try .fileChange(FileChangeEvent(from: $0)) },
        "file_created": { try .fileCreated(FileCreatedEvent(from: $0)) },
        "file_deleted": { try .fileDeleted(FileDeletedEvent(from: $0)) },
        "file_public": { try .filePublic(FilePublicEvent(from: $0)) },
        "file_shared": { try .fileShared(FileSharedEvent(from: $0)) },
        "file_unshared": { try .fileUnshared(FileUnsharedEvent(from: $0)) },
        "goodbye": { try .goodbye(GoodbyeEvent(from: $0)) },
        "grid_migration_finished": { try .gridMigrationFinished(GridMigrationFinishedEvent(from: $0)) },
        "grid_migration_started": { try .gridMigrationStarted(GridMigrationStartedEvent(from: $0)) },
        "group_archive": { try .groupArchive(GroupArchiveEvent(from: $0)) },
        "group_close": { try .groupClose(GroupCloseEvent(from: $0)) },
        "group_deleted": { try .groupDeleted(GroupDeletedEvent(from: $0)) },
        "group_history_changed": { try .groupHistoryChanged(GroupHistoryChangedEvent(from: $0)) },
        "group_left": { try .groupLeft(GroupLeftEvent(from: $0)) },
        "group_open": { try .groupOpen(GroupOpenEvent(from: $0)) },
        "group_rename": { try .groupRename(GroupRenameEvent(from: $0)) },
        "group_unarchive": { try .groupUnarchive(GroupUnarchiveEvent(from: $0)) },
        "im_close": { try .imClose(IMCloseEvent(from: $0)) },
        "im_created": { try .imCreated(IMCreatedEvent(from: $0)) },
        "im_history_changed": { try .imHistoryChanged(IMHistoryChangedEvent(from: $0)) },
        "im_open": { try .imOpen(IMOpenEvent(from: $0)) },
        "invite_requested": { try .inviteRequested(InviteRequestedEvent(from: $0)) },
        "link_shared": { try .linkShared(LinkSharedEvent(from: $0)) },
        "member_joined_channel": { try .memberJoinedChannel(MemberJoinedChannelEvent(from: $0)) },
        "member_left_channel": { try .memberLeftChannel(MemberLeftChannelEvent(from: $0)) },
        "pin_added": { try .pinAdded(PinAddedEvent(from: $0)) },
        "pin_removed": { try .pinRemoved(PinRemovedEvent(from: $0)) },
        "reaction_added": { try .reactionAdded(ReactionAddedEvent(from: $0)) },
        "reaction_removed": { try .reactionRemoved(ReactionRemovedEvent(from: $0)) },
        "scope_denied": { try .scopeDenied(ScopeDeniedEvent(from: $0)) },
        "scope_granted": { try .scopeGranted(ScopeGrantedEvent(from: $0)) },
        "star_added": { try .starAdded(StarAddedEvent(from: $0)) },
        "star_removed": { try .starRemoved(StarRemovedEvent(from: $0)) },
        "subteam_created": { try .subteamCreated(SubteamCreatedEvent(from: $0)) },
        "subteam_members_changed": { try .subteamMembersChanged(SubteamMembersChangedEvent(from: $0)) },
        "subteam_self_added": { try .subteamSelfAdded(SubteamSelfAddedEvent(from: $0)) },
        "subteam_self_removed": { try .subteamSelfRemoved(SubteamSelfRemovedEvent(from: $0)) },
        "subteam_updated": { try .subteamUpdated(SubteamUpdatedEvent(from: $0)) },
        "team_access_granted": { try .teamAccessGranted(TeamAccessGrantedEvent(from: $0)) },
        "team_access_revoked": { try .teamAccessRevoked(TeamAccessRevokedEvent(from: $0)) },
        "team_domain_change": { try .teamDomainChange(TeamDomainChangeEvent(from: $0)) },
        "team_join": { try .teamJoin(TeamJoinEvent(from: $0)) },
        "team_rename": { try .teamRename(TeamRenameEvent(from: $0)) },
        "tokens_revoked": { try .tokensRevoked(TokensRevokedEvent(from: $0)) },
        "user_change": { try .userChange(UserChangeEvent(from: $0)) },
        "user_huddle_changed": { try .userHuddleChanged(UserHuddleChangedEvent(from: $0)) },
        "user_profile_changed": { try .userProfileChanged(UserProfileChangedEvent(from: $0)) },
        "user_status_changed": { try .userStatusChanged(UserStatusChangedEvent(from: $0)) },
        "workflow_deleted": { try .workflowDeleted(WorkflowDeletedEvent(from: $0)) },
        "workflow_published": { try .workflowPublished(WorkflowPublishedEvent(from: $0)) },
        "workflow_step_deleted": { try .workflowStepDeleted(WorkflowStepDeletedEvent(from: $0)) },
        "workflow_step_execute": { try .workflowStepExecute(WorkflowStepExecuteEvent(from: $0)) },
        "workflow_unpublished": { try .workflowUnpublished(WorkflowUnpublishedEvent(from: $0)) },
    ]

    /// Decoders for event types with subtypes, keyed by `type` and then `subtype` (`nil` for none).
    private static let subtypeDecoders: [String: [String?: Decode]] = [
        "message": [
            nil: { try .message(MessageEvent(from: $0)) },
            "bot_message": { try .messageBot(MessageBotEvent(from: $0)) },
            "channel_archive": { try .messageChannelArchive(MessageChannelArchiveEvent(from: $0)) },
            "channel_join": { try .messageChannelJoin(MessageChannelJoinEvent(from: $0)) },
            "channel_leave": { try .messageChannelLeave(MessageChannelLeaveEvent(from: $0)) },
            "channel_name": { try .messageChannelName(MessageChannelNameEvent(from: $0)) },
            "channel_posting_permissions": { try .messageChannelPostingPermissions(MessageChannelPostingPermissionsEvent(from: $0)) },
            "channel_purpose": { try .messageChannelPurpose(MessageChannelPurposeEvent(from: $0)) },
            "channel_topic": { try .messageChannelTopic(MessageChannelTopicEvent(from: $0)) },
            "channel_unarchive": { try .messageChannelUnarchive(MessageChannelUnarchiveEvent(from: $0)) },
            "ekm_access_denied": { try .messageEkmAccessDenied(MessageEkmAccessDeniedEvent(from: $0)) },
            "file_share": { try .messageFileShare(MessageFileShareEvent(from: $0)) },
            "group_topic": { try .messageGroupTopic(MessageGroupTopicEvent(from: $0)) },
            "me_message": { try .messageMe(MessageMeEvent(from: $0)) },
            "message_changed": { try .messageChanged(MessageChangedEvent(from: $0)) },
            "message_deleted": { try .messageDeleted(MessageDeletedEvent(from: $0)) },
            "message_replied": { try .messageReplied(MessageRepliedEvent(from: $0)) },
            "thread_broadcast": { try .messageThreadBroadcast(MessageThreadBroadcastEvent(from: $0)) },
        ],
    ]

    /// Returns the contained event as a SlackEvent
    public var payload: (any SlackEvent)? {
        switch self {
        case let .agentSessionStopped(event):
            event
        case let .agentSessionTitleChanged(event):
            event
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
        case let .codeChannelAction(event):
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

    // `==` and `hash(into:)` compare `payload`, whose type identifies the case, instead of being
    // synthesized as a `switch` over every case.
    public static func == (lhs: Event, rhs: Event) -> Bool {
        switch (lhs.payload, rhs.payload) {
        case let (lhsPayload?, rhsPayload?):
            return AnyHashable(lhsPayload) == AnyHashable(rhsPayload)
        case (nil, nil):
            guard case let .unsupported(lhsType) = lhs, case let .unsupported(rhsType) = rhs else { return false }
            return lhsType == rhsType
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        if let payload {
            hasher.combine(AnyHashable(payload))
        } else if case let .unsupported(type) = self {
            hasher.combine(type)
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
