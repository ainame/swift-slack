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

/// - Remark: Generated from `#/components/schemas/Settings`.
public struct Settings: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Settings/allowed_ip_address_ranges`.
    public var allowedIpAddressRanges: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Settings/background_color`.
    public var backgroundColor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Settings/description`.
    public var description: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Settings/event_subscriptions`.
    public var eventSubscriptions: EventSubscriptions?
    /// - Remark: Generated from `#/components/schemas/Settings/function_runtime`.
    public var functionRuntime: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Settings/hermes_app_type`.
    public var hermesAppType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Settings/interactivity`.
    public var interactivity: Interactivity?
    /// - Remark: Generated from `#/components/schemas/Settings/is_mcp_enabled`.
    public var isMcpEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Settings/long_description`.
    public var longDescription: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Settings/org_deploy_enabled`.
    public var orgDeployEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Settings/socket_mode_enabled`.
    public var socketModeEnabled: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Settings/token_rotation_enabled`.
    public var tokenRotationEnabled: Swift.Bool?
    /// Creates a new `Settings`.
    ///
    /// - Parameters:
    ///   - allowedIpAddressRanges:
    ///   - backgroundColor:
    ///   - description:
    ///   - eventSubscriptions:
    ///   - functionRuntime:
    ///   - hermesAppType:
    ///   - interactivity:
    ///   - isMcpEnabled:
    ///   - longDescription:
    ///   - orgDeployEnabled:
    ///   - socketModeEnabled:
    ///   - tokenRotationEnabled:
    public init(
        allowedIpAddressRanges: [Swift.String]? = nil,
        backgroundColor: Swift.String? = nil,
        description: Swift.String? = nil,
        eventSubscriptions: EventSubscriptions? = nil,
        functionRuntime: Swift.String? = nil,
        hermesAppType: Swift.String? = nil,
        interactivity: Interactivity? = nil,
        isMcpEnabled: Swift.Bool? = nil,
        longDescription: Swift.String? = nil,
        orgDeployEnabled: Swift.Bool? = nil,
        socketModeEnabled: Swift.Bool? = nil,
        tokenRotationEnabled: Swift.Bool? = nil,
    ) {
        self.allowedIpAddressRanges = allowedIpAddressRanges
        self.backgroundColor = backgroundColor
        self.description = description
        self.eventSubscriptions = eventSubscriptions
        self.functionRuntime = functionRuntime
        self.hermesAppType = hermesAppType
        self.interactivity = interactivity
        self.isMcpEnabled = isMcpEnabled
        self.longDescription = longDescription
        self.orgDeployEnabled = orgDeployEnabled
        self.socketModeEnabled = socketModeEnabled
        self.tokenRotationEnabled = tokenRotationEnabled
    }

    public enum CodingKeys: String, CodingKey {
        case allowedIpAddressRanges = "allowed_ip_address_ranges"
        case backgroundColor = "background_color"
        case description
        case eventSubscriptions = "event_subscriptions"
        case functionRuntime = "function_runtime"
        case hermesAppType = "hermes_app_type"
        case interactivity
        case isMcpEnabled = "is_mcp_enabled"
        case longDescription = "long_description"
        case orgDeployEnabled = "org_deploy_enabled"
        case socketModeEnabled = "socket_mode_enabled"
        case tokenRotationEnabled = "token_rotation_enabled"
    }
}
