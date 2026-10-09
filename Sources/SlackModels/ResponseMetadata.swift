import Foundation
import OpenAPIRuntime

/// Metadata attached to Web API responses, such as the cursor for the next page.
///
/// Mirrors `com.slack.api.model.ResponseMetadata` in java-slack-sdk. This is hand-written because
/// only some response fixtures include `next_cursor`, and the generated model kept the fields of
/// whichever fixture was merged last. `messages` and `warnings` keep the types of the previously
/// generated model for source compatibility.
public struct ResponseMetadata: Codable, Hashable, Sendable {
    public var messages: [Swift.String]?
    public var nextCursor: Swift.String?
    public var warnings: [OpenAPIRuntime.OpenAPIValueContainer]?

    public init(
        messages: [Swift.String]? = nil,
        nextCursor: Swift.String? = nil,
        warnings: [OpenAPIRuntime.OpenAPIValueContainer]? = nil,
    ) {
        self.messages = messages
        self.nextCursor = nextCursor
        self.warnings = warnings
    }

    public enum CodingKeys: String, CodingKey {
        case messages
        case nextCursor = "next_cursor"
        case warnings
    }
}
