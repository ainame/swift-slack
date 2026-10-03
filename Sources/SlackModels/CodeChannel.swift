/// Conversation properties from java-slack-sdk's `ConversationProperties.CodeChannel`.
public struct CodeChannel: Codable, Hashable, Sendable {
    public var contextBarItems: [ContextBarItem]?

    public init(
        contextBarItems: [ContextBarItem]? = nil,
    ) {
        self.contextBarItems = contextBarItems
    }

    public enum CodingKeys: String, CodingKey {
        case contextBarItems = "context_bar_items"
    }

    public struct ContextBarItem: Codable, Hashable, Sendable {
        public var key: String?
        public var label: String?
        public var icon: String?
        public var url: String?
        public var botUserId: String?

        public init(
            key: String? = nil,
            label: String? = nil,
            icon: String? = nil,
            url: String? = nil,
            botUserId: String? = nil,
        ) {
            self.key = key
            self.label = label
            self.icon = icon
            self.url = url
            self.botUserId = botUserId
        }

        public enum CodingKeys: String, CodingKey {
            case key
            case label
            case icon
            case url
            case botUserId = "bot_user_id"
        }
    }
}
