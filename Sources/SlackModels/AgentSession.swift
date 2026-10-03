/// Conversation properties from java-slack-sdk's `ConversationProperties.AgentSession`.
public struct AgentSession: Codable, Hashable, Sendable {
    public var status: String?
    public var agentBotUserIds: [String]?
    public var encodedAgentBotUserIds: [String]?
    public var title: String?
    public var originLink: OriginLink?

    public init(
        status: String? = nil,
        agentBotUserIds: [String]? = nil,
        encodedAgentBotUserIds: [String]? = nil,
        title: String? = nil,
        originLink: OriginLink? = nil,
    ) {
        self.status = status
        self.agentBotUserIds = agentBotUserIds
        self.encodedAgentBotUserIds = encodedAgentBotUserIds
        self.title = title
        self.originLink = originLink
    }

    public enum CodingKeys: String, CodingKey {
        case status
        case agentBotUserIds = "agent_bot_user_ids"
        case encodedAgentBotUserIds = "encoded_agent_bot_user_ids"
        case title
        case originLink = "origin_link"
    }

    public struct OriginLink: Codable, Hashable, Sendable {
        public var channelId: String?
        public var ts: String?

        public init(
            channelId: String? = nil,
            ts: String? = nil,
        ) {
            self.channelId = channelId
            self.ts = ts
        }

        public enum CodingKeys: String, CodingKey {
            case channelId = "channel_id"
            case ts
        }
    }
}
