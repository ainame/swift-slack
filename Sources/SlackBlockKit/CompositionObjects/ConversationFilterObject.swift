import Foundation

public struct ConversationFilterObject: Codable, Hashable, Sendable {
    public let include: [ConversationType]?
    public let excludeExternalSharedChannels: Bool?
    public let excludeBotUsers: Bool?

    public init(include: [ConversationType]? = nil, excludeExternalSharedChannels: Bool? = nil, excludeBotUsers: Bool? = nil) {
        self.include = include
        self.excludeExternalSharedChannels = excludeExternalSharedChannels
        self.excludeBotUsers = excludeBotUsers
    }

    private enum CodingKeys: String, CodingKey {
        case include
        case excludeExternalSharedChannels = "exclude_external_shared_channels"
        case excludeBotUsers = "exclude_bot_users"
    }
}

public enum ConversationType: String, Codable, Hashable, Sendable {
    case im
    case mpim
    case `private`
    case `public`
}
