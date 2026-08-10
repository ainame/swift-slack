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

/// - Remark: Generated from `#/components/schemas/RecordField`.
public struct RecordField: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/RecordField/checkbox`.
    public var checkbox: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/RecordField/column_id`.
    public var columnId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/RecordField/key`.
    public var key: Swift.String?
    /// - Remark: Generated from `#/components/schemas/RecordField/rich_text`.
    public var richText: [DescriptionBlock]?
    /// - Remark: Generated from `#/components/schemas/RecordField/text`.
    public var text: Swift.String?
    /// - Remark: Generated from `#/components/schemas/RecordField/value`.
    public var value: Swift.Bool?
    /// Creates a new `RecordField`.
    ///
    /// - Parameters:
    ///   - checkbox:
    ///   - columnId:
    ///   - key:
    ///   - richText:
    ///   - text:
    ///   - value:
    public init(
        checkbox: Swift.Bool? = nil,
        columnId: Swift.String? = nil,
        key: Swift.String? = nil,
        richText: [DescriptionBlock]? = nil,
        text: Swift.String? = nil,
        value: Swift.Bool? = nil,
    ) {
        self.checkbox = checkbox
        self.columnId = columnId
        self.key = key
        self.richText = richText
        self.text = text
        self.value = value
    }

    public enum CodingKeys: String, CodingKey {
        case checkbox
        case columnId = "column_id"
        case key
        case richText = "rich_text"
        case text
        case value
    }
}
