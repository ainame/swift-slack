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

/// - Remark: Generated from `#/components/schemas/ChannelWorkflow`.
public struct ChannelWorkflow: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/ChannelWorkflow/title`.
    public var title: Swift.String?
    /// - Remark: Generated from `#/components/schemas/ChannelWorkflow/workflow_trigger_id`.
    public var workflowTriggerId: Swift.String?
    /// Creates a new `ChannelWorkflow`.
    ///
    /// - Parameters:
    ///   - title:
    ///   - workflowTriggerId:
    public init(
        title: Swift.String? = nil,
        workflowTriggerId: Swift.String? = nil,
    ) {
        self.title = title
        self.workflowTriggerId = workflowTriggerId
    }

    public enum CodingKeys: String, CodingKey {
        case title
        case workflowTriggerId = "workflow_trigger_id"
    }
}
