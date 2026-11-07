import Foundation

/// Displays an authentication provider and its connection state.
/// Mirrors upstream java-slack-sdk AuthProviderBlock. Text fields use plain text.
public struct AuthProviderBlock: Codable, Hashable, Sendable {
    public let type: String
    public let value: String
    public let name: TextObject
    public let isConnected: Bool
    public let description: TextObject?
    public let iconUrl: URL?
    public let authUrl: URL?
    public let disconnectUrl: URL?
    public let connectedIdentity: TextObject?
    public let connectedContext: TextObject?
    public let accessory: OverflowMenuElement?
    public let fallback: [Block]?
    public let blockId: String?

    public init(
        value: String,
        name: TextObject,
        isConnected: Bool,
        description: TextObject? = nil,
        iconUrl: URL? = nil,
        authUrl: URL? = nil,
        disconnectUrl: URL? = nil,
        connectedIdentity: TextObject? = nil,
        connectedContext: TextObject? = nil,
        accessory: OverflowMenuElement? = nil,
        fallback: [Block]? = nil,
        blockId: String? = nil,
    ) {
        type = "auth_provider"
        self.value = value
        self.name = name
        self.isConnected = isConnected
        self.description = description
        self.iconUrl = iconUrl
        self.authUrl = authUrl
        self.disconnectUrl = disconnectUrl
        self.connectedIdentity = connectedIdentity
        self.connectedContext = connectedContext
        self.accessory = accessory
        self.fallback = fallback
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case name
        case isConnected = "is_connected"
        case description
        case iconUrl = "icon_url"
        case authUrl = "auth_url"
        case disconnectUrl = "disconnect_url"
        case connectedIdentity = "connected_identity"
        case connectedContext = "connected_context"
        case accessory
        case fallback
        case blockId = "block_id"
    }
}
