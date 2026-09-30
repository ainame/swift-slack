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

/// - Remark: Generated from `#/components/schemas/Args`.
public struct Args: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Args/error`.
    public var error: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Args/foo`.
    public var foo: Swift.String?
    /// Creates a new `Args`.
    ///
    /// - Parameters:
    ///   - error:
    ///   - foo:
    public init(
        error: Swift.String? = nil,
        foo: Swift.String? = nil,
    ) {
        self.error = error
        self.foo = foo
    }

    public enum CodingKeys: String, CodingKey {
        case error
        case foo
    }
}
