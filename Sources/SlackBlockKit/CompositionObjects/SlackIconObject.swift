import Foundation

/// A built-in Slack icon, identified by name.
public struct SlackIconObject: Codable, Hashable, Sendable {
    public let type: String
    public let name: String

    public init(
        name: String,
    ) {
        type = "icon"
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
}
