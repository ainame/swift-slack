/// Conversation properties from java-slack-sdk's `ConversationProperties.RecordChannel`.
public struct RecordChannel: Codable, Hashable, Sendable {
    public var recordId: String?
    public var recordType: String?
    public var recordLabel: String?
    public var recordLabelPlural: String?

    public init(
        recordId: String? = nil,
        recordType: String? = nil,
        recordLabel: String? = nil,
        recordLabelPlural: String? = nil,
    ) {
        self.recordId = recordId
        self.recordType = recordType
        self.recordLabel = recordLabel
        self.recordLabelPlural = recordLabelPlural
    }

    public enum CodingKeys: String, CodingKey {
        case recordId = "record_id"
        case recordType = "record_type"
        case recordLabel = "record_label"
        case recordLabelPlural = "record_label_plural"
    }
}
