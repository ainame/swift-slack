import Foundation
import OpenAPIRuntime

public struct ContextBlock: Codable, Hashable, Sendable {
    public let type: String
    public let elements: [ContextElementType]
    public let blockId: String?

    public init(elements: [ContextElementType], blockId: String? = nil) {
        type = "context"
        self.elements = elements
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case elements
        case blockId = "block_id"
    }
}

public enum ContextElementType: Codable, Hashable, Sendable {
    case text(TextObject)
    case image(ImageElement)
    case unknown(type: String, payload: OpenAPIObjectContainer)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "plain_text", "mrkdwn":
            self = try .text(container.decode(TextObject.self))
        case "image":
            self = try .image(container.decode(ImageElement.self))
        default:
            self = try .unknown(type: type, payload: OpenAPIObjectContainer(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .text(element):
            try container.encode(element)
        case let .image(element):
            try container.encode(element)
        case let .unknown(type, payload):
            try container.encode(OpenAPIObjectContainer.unknown(type: type, payload: payload))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}
