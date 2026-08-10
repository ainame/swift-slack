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

/// - Remark: Generated from `#/components/schemas/Subtask`.
public struct Subtask: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Subtask/created_by`.
    public var createdBy: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Subtask/date_created`.
    public var dateCreated: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Subtask/fields`.
    public var fields: [SubtaskField]?
    /// - Remark: Generated from `#/components/schemas/Subtask/id`.
    public var id: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Subtask/is_subscribed`.
    public var isSubscribed: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Subtask/list_id`.
    public var listId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Subtask/updated_by`.
    public var updatedBy: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Subtask/updated_timestamp`.
    public var updatedTimestamp: Swift.String?
    /// Creates a new `Subtask`.
    ///
    /// - Parameters:
    ///   - createdBy:
    ///   - dateCreated:
    ///   - fields:
    ///   - id:
    ///   - isSubscribed:
    ///   - listId:
    ///   - updatedBy:
    ///   - updatedTimestamp:
    public init(
        createdBy: Swift.String? = nil,
        dateCreated: Swift.Int? = nil,
        fields: [SubtaskField]? = nil,
        id: Swift.String? = nil,
        isSubscribed: Swift.Bool? = nil,
        listId: Swift.String? = nil,
        updatedBy: Swift.String? = nil,
        updatedTimestamp: Swift.String? = nil,
    ) {
        self.createdBy = createdBy
        self.dateCreated = dateCreated
        self.fields = fields
        self.id = id
        self.isSubscribed = isSubscribed
        self.listId = listId
        self.updatedBy = updatedBy
        self.updatedTimestamp = updatedTimestamp
    }

    public enum CodingKeys: String, CodingKey {
        case createdBy = "created_by"
        case dateCreated = "date_created"
        case fields
        case id
        case isSubscribed = "is_subscribed"
        case listId = "list_id"
        case updatedBy = "updated_by"
        case updatedTimestamp = "updated_timestamp"
    }
}
