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

/// - Remark: Generated from `#/components/schemas/Workflow`.
public struct Workflow: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Workflow/trigger`.
    public var trigger: Trigger?
    /// Creates a new `Workflow`.
    ///
    /// - Parameters:
    ///   - trigger:
    public init(trigger: Trigger? = nil) {
        self.trigger = trigger
    }

    public enum CodingKeys: String, CodingKey {
        case trigger
    }
}
