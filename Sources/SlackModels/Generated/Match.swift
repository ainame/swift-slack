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

/// - Remark: Generated from `#/components/schemas/Match`.
public struct Match: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Match/attachments`.
    public var attachments: [Attachment]?
    /// - Remark: Generated from `#/components/schemas/Match/blocks`.
    public var blocks: [Block]?
    /// - Remark: Generated from `#/components/schemas/Match/channel`.
    public var channel: Channel?
    /// - Remark: Generated from `#/components/schemas/Match/db_message`.
    public var dbMessage: Message?
    /// - Remark: Generated from `#/components/schemas/Match/files`.
    public var files: [FileElement]?
    /// - Remark: Generated from `#/components/schemas/Match/iid`.
    public var iid: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/is_mpim`.
    public var isMpim: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Match/no_reactions`.
    public var noReactions: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Match/permalink`.
    public var permalink: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/previous`.
    public var previous: Previous?
    /// - Remark: Generated from `#/components/schemas/Match/previous_2`.
    public var previous2: Previous?
    /// - Remark: Generated from `#/components/schemas/Match/score`.
    public var score: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Match/team`.
    public var team: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/text`.
    public var text: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/ts`.
    public var ts: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/type`.
    public var _type: Swift.String
    /// - Remark: Generated from `#/components/schemas/Match/user`.
    public var user: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Match/username`.
    public var username: Swift.String?
    /// Creates a new `Match`.
    ///
    /// - Parameters:
    ///   - attachments:
    ///   - blocks:
    ///   - channel:
    ///   - dbMessage:
    ///   - files:
    ///   - iid:
    ///   - isMpim:
    ///   - noReactions:
    ///   - permalink:
    ///   - previous:
    ///   - previous2:
    ///   - score:
    ///   - team:
    ///   - text:
    ///   - ts:
    ///   - _type:
    ///   - user:
    ///   - username:
    public init(
        attachments: [Attachment]? = nil,
        blocks: [Block]? = nil,
        channel: Channel? = nil,
        dbMessage: Message? = nil,
        files: [FileElement]? = nil,
        iid: Swift.String? = nil,
        isMpim: Swift.Bool? = nil,
        noReactions: Swift.Bool? = nil,
        permalink: Swift.String? = nil,
        previous: Previous? = nil,
        previous2: Previous? = nil,
        score: Swift.Int? = nil,
        team: Swift.String? = nil,
        text: Swift.String? = nil,
        ts: Swift.String? = nil,
        _type: Swift.String,
        user: Swift.String? = nil,
        username: Swift.String? = nil,
    ) {
        self.attachments = attachments
        self.blocks = blocks
        self.channel = channel
        self.dbMessage = dbMessage
        self.files = files
        self.iid = iid
        self.isMpim = isMpim
        self.noReactions = noReactions
        self.permalink = permalink
        self.previous = previous
        self.previous2 = previous2
        self.score = score
        self.team = team
        self.text = text
        self.ts = ts
        self._type = _type
        self.user = user
        self.username = username
    }

    public enum CodingKeys: String, CodingKey {
        case attachments
        case blocks
        case channel
        case dbMessage = "db_message"
        case files
        case iid
        case isMpim = "is_mpim"
        case noReactions = "no_reactions"
        case permalink
        case previous
        case previous2 = "previous_2"
        case score
        case team
        case text
        case ts
        case _type = "type"
        case user
        case username
    }
}
