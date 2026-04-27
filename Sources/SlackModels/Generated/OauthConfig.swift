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

/// - Remark: Generated from `#/components/schemas/OauthConfig`.
public struct OauthConfig: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/OauthConfig/pkce_enabled`.
    public var pkceEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/OauthConfig/redirect_urls`.
    public var redirectUrls: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/OauthConfig/scopes`.
    public var scopes: Scopes?
    /// - Remark: Generated from `#/components/schemas/OauthConfig/token_management_enabled`.
    public var tokenManagementEnabled: Swift.Bool?
    /// Creates a new `OauthConfig`.
    ///
    /// - Parameters:
    ///   - pkceEnabled:
    ///   - redirectUrls:
    ///   - scopes:
    ///   - tokenManagementEnabled:
    public init(
        pkceEnabled: Swift.Bool? = nil,
        redirectUrls: [Swift.String]? = nil,
        scopes: Scopes? = nil,
        tokenManagementEnabled: Swift.Bool? = nil,
    ) {
        self.pkceEnabled = pkceEnabled
        self.redirectUrls = redirectUrls
        self.scopes = scopes
        self.tokenManagementEnabled = tokenManagementEnabled
    }

    public enum CodingKeys: String, CodingKey {
        case pkceEnabled = "pkce_enabled"
        case redirectUrls = "redirect_urls"
        case scopes
        case tokenManagementEnabled = "token_management_enabled"
    }
}
