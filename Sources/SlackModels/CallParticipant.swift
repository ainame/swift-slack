import Foundation

/// A participant in a call registered through the Calls API.
///
/// A participant is either a Slack user (`slackId`) or an external user (`externalId`,
/// `displayName`, `avatarUrl`). Mirrors `com.slack.api.model.CallParticipant` in java-slack-sdk.
public struct CallParticipant: Codable, Hashable, Sendable {
    public var slackId: Swift.String?
    public var externalId: Swift.String?
    public var displayName: Swift.String?
    public var avatarUrl: Swift.String?

    public init(
        slackId: Swift.String? = nil,
        externalId: Swift.String? = nil,
        displayName: Swift.String? = nil,
        avatarUrl: Swift.String? = nil,
    ) {
        self.slackId = slackId
        self.externalId = externalId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    private enum CodingKeys: String, CodingKey {
        case slackId = "slack_id"
        case externalId = "external_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}
