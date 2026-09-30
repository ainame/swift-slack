import Foundation

/// A call registered through the Calls API (`calls.add`, `calls.info`, and related methods).
///
/// Mirrors `com.slack.api.model.Call` in java-slack-sdk. This is hand-written because the
/// generated shape collided with the unrelated `call` object in message call blocks.
public struct Call: Codable, Hashable, Sendable {
    public var id: Swift.String?
    public var dateStart: Swift.Int?
    public var externalUniqueId: Swift.String?
    public var joinUrl: Swift.String?
    public var dateEnd: Swift.Int?
    public var channels: [Swift.String]?
    public var externalDisplayId: Swift.String?
    public var title: Swift.String?
    public var desktopAppJoinUrl: Swift.String?
    public var users: [CallParticipant]?

    public init(
        id: Swift.String? = nil,
        dateStart: Swift.Int? = nil,
        externalUniqueId: Swift.String? = nil,
        joinUrl: Swift.String? = nil,
        dateEnd: Swift.Int? = nil,
        channels: [Swift.String]? = nil,
        externalDisplayId: Swift.String? = nil,
        title: Swift.String? = nil,
        desktopAppJoinUrl: Swift.String? = nil,
        users: [CallParticipant]? = nil,
    ) {
        self.id = id
        self.dateStart = dateStart
        self.externalUniqueId = externalUniqueId
        self.joinUrl = joinUrl
        self.dateEnd = dateEnd
        self.channels = channels
        self.externalDisplayId = externalDisplayId
        self.title = title
        self.desktopAppJoinUrl = desktopAppJoinUrl
        self.users = users
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case dateStart = "date_start"
        case externalUniqueId = "external_unique_id"
        case joinUrl = "join_url"
        case dateEnd = "date_end"
        case channels
        case externalDisplayId = "external_display_id"
        case title
        case desktopAppJoinUrl = "desktop_app_join_url"
        case users
    }
}
