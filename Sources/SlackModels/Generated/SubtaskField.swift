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

/// - Remark: Generated from `#/components/schemas/SubtaskField`.
public struct SubtaskField: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/SubtaskField/checkbox`.
    public var checkbox: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/SubtaskField/column_id`.
    public var columnId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SubtaskField/key`.
    public var key: Swift.String?
    /// - Remark: Generated from `#/components/schemas/SubtaskField/value`.
    public var value: Swift.Bool?
    /// Creates a new `SubtaskField`.
    ///
    /// - Parameters:
    ///   - checkbox:
    ///   - columnId:
    ///   - key:
    ///   - value:
    public init(
        checkbox: Swift.Bool? = nil,
        columnId: Swift.String? = nil,
        key: Swift.String? = nil,
        value: Swift.Bool? = nil,
    ) {
        self.checkbox = checkbox
        self.columnId = columnId
        self.key = key
        self.value = value
    }

    public enum CodingKeys: String, CodingKey {
        case checkbox
        case columnId = "column_id"
        case key
        case value
    }
}
