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

/// - Remark: Generated from `#/components/schemas/Properties`.
public struct Properties: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Properties/at_channel_restricted`.
    public var atChannelRestricted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Properties/at_here_restricted`.
    public var atHereRestricted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Properties/canvas`.
    public var canvas: Canvas?
    /// - Remark: Generated from `#/components/schemas/Properties/has_slack_connect_invite_created`.
    public var hasSlackConnectInviteCreated: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Properties/huddles_restricted`.
    public var huddlesRestricted: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Properties/is_dormant`.
    public var isDormant: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Properties/meeting_notes`.
    public var meetingNotes: MeetingNotes?
    /// - Remark: Generated from `#/components/schemas/Properties/posting_restricted_to`.
    public var postingRestrictedTo: PostingRestrictedTo?
    /// - Remark: Generated from `#/components/schemas/Properties/tabs`.
    public var tabs: [Tab]?
    /// - Remark: Generated from `#/components/schemas/Properties/tabz`.
    public var tabz: [Tab]?
    /// - Remark: Generated from `#/components/schemas/Properties/threads_restricted_to`.
    public var threadsRestrictedTo: ThreadsRestrictedTo?
    /// - Remark: Generated from `#/components/schemas/Properties/agent_session`.
    public var agentSession: AgentSession?
    /// - Remark: Generated from `#/components/schemas/Properties/code_channel`.
    public var codeChannel: CodeChannel?
    /// - Remark: Generated from `#/components/schemas/Properties/record_channel`.
    public var recordChannel: RecordChannel?
    /// - Remark: Generated from `#/components/schemas/Properties/use_case`.
    public var useCase: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Properties/channel_workflows`.
    public var channelWorkflows: [ChannelWorkflow]?
    /// Creates a new `Properties`.
    ///
    /// - Parameters:
    ///   - atChannelRestricted:
    ///   - atHereRestricted:
    ///   - canvas:
    ///   - hasSlackConnectInviteCreated:
    ///   - huddlesRestricted:
    ///   - isDormant:
    ///   - meetingNotes:
    ///   - postingRestrictedTo:
    ///   - tabs:
    ///   - tabz:
    ///   - threadsRestrictedTo:
    ///   - agentSession:
    ///   - codeChannel:
    ///   - recordChannel:
    ///   - useCase:
    ///   - channelWorkflows:
    public init(
        atChannelRestricted: Swift.Bool? = nil,
        atHereRestricted: Swift.Bool? = nil,
        canvas: Canvas? = nil,
        hasSlackConnectInviteCreated: Swift.Bool? = nil,
        huddlesRestricted: Swift.Bool? = nil,
        isDormant: Swift.Bool? = nil,
        meetingNotes: MeetingNotes? = nil,
        postingRestrictedTo: PostingRestrictedTo? = nil,
        tabs: [Tab]? = nil,
        tabz: [Tab]? = nil,
        threadsRestrictedTo: ThreadsRestrictedTo? = nil,
        agentSession: AgentSession? = nil,
        codeChannel: CodeChannel? = nil,
        recordChannel: RecordChannel? = nil,
        useCase: Swift.String? = nil,
        channelWorkflows: [ChannelWorkflow]? = nil,
    ) {
        self.atChannelRestricted = atChannelRestricted
        self.atHereRestricted = atHereRestricted
        self.canvas = canvas
        self.hasSlackConnectInviteCreated = hasSlackConnectInviteCreated
        self.huddlesRestricted = huddlesRestricted
        self.isDormant = isDormant
        self.meetingNotes = meetingNotes
        self.postingRestrictedTo = postingRestrictedTo
        self.tabs = tabs
        self.tabz = tabz
        self.threadsRestrictedTo = threadsRestrictedTo
        self.agentSession = agentSession
        self.codeChannel = codeChannel
        self.recordChannel = recordChannel
        self.useCase = useCase
        self.channelWorkflows = channelWorkflows
    }

    public enum CodingKeys: String, CodingKey {
        case atChannelRestricted = "at_channel_restricted"
        case atHereRestricted = "at_here_restricted"
        case canvas
        case hasSlackConnectInviteCreated = "has_slack_connect_invite_created"
        case huddlesRestricted = "huddles_restricted"
        case isDormant = "is_dormant"
        case meetingNotes = "meeting_notes"
        case postingRestrictedTo = "posting_restricted_to"
        case tabs
        case tabz
        case threadsRestrictedTo = "threads_restricted_to"
        case agentSession = "agent_session"
        case codeChannel = "code_channel"
        case recordChannel = "record_channel"
        case useCase = "use_case"
        case channelWorkflows = "channel_workflows"
    }
}
