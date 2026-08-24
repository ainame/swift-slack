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

/// - Remark: Generated from `#/components/schemas/SchemaOptions`.
public struct SchemaOptions: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/choices`.
    public var choices: [Choice]?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/date_format`.
    public var dateFormat: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/default_value_typed`.
    public var defaultValueTyped: DefaultValueTyped?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/emoji`.
    public var emoji: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/emoji_team_id`.
    public var emojiTeamId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/format`.
    public var format: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/max`.
    public var max: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/notify_users`.
    public var notifyUsers: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/precision`.
    public var precision: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/SchemaOptions/show_member_name`.
    public var showMemberName: Swift.Bool?
    /// Creates a new `SchemaOptions`.
    ///
    /// - Parameters:
    ///   - choices:
    ///   - dateFormat:
    ///   - defaultValueTyped:
    ///   - emoji:
    ///   - emojiTeamId:
    ///   - format:
    ///   - max:
    ///   - notifyUsers:
    ///   - precision:
    ///   - showMemberName:
    public init(
        choices: [Choice]? = nil,
        dateFormat: Swift.String? = nil,
        defaultValueTyped: DefaultValueTyped? = nil,
        emoji: Swift.String? = nil,
        emojiTeamId: Swift.String? = nil,
        format: Swift.String? = nil,
        max: Swift.Int? = nil,
        notifyUsers: Swift.Bool? = nil,
        precision: Swift.Int? = nil,
        showMemberName: Swift.Bool? = nil,
    ) {
        self.choices = choices
        self.dateFormat = dateFormat
        self.defaultValueTyped = defaultValueTyped
        self.emoji = emoji
        self.emojiTeamId = emojiTeamId
        self.format = format
        self.max = max
        self.notifyUsers = notifyUsers
        self.precision = precision
        self.showMemberName = showMemberName
    }

    public enum CodingKeys: String, CodingKey {
        case choices
        case dateFormat = "date_format"
        case defaultValueTyped = "default_value_typed"
        case emoji
        case emojiTeamId = "emoji_team_id"
        case format
        case max
        case notifyUsers = "notify_users"
        case precision
        case showMemberName = "show_member_name"
    }
}
