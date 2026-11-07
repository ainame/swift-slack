import Foundation
import OpenAPIRuntime

public struct ContextActionsBlock: Codable, Hashable, Sendable {
    public let type: String
    public let elements: [ContextActionsElementType]
    public let blockId: String?

    public init(elements: [ContextActionsElementType], blockId: String? = nil) {
        type = "context_actions"
        self.elements = elements
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case elements
        case blockId = "block_id"
    }
}

public enum ContextActionsElementType: Codable, Hashable, Sendable {
    case feedbackButtons(FeedbackButtonsElement)
    case iconButton(IconButtonElement)
    case unknown(type: String, payload: OpenAPIObjectContainer)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "feedback_buttons":
            self = try .feedbackButtons(container.decode(FeedbackButtonsElement.self))
        case "icon_button":
            self = try .iconButton(container.decode(IconButtonElement.self))
        default:
            self = try .unknown(type: type, payload: OpenAPIObjectContainer(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .feedbackButtons(element):
            try container.encode(element)
        case let .iconButton(element):
            try container.encode(element)
        case let .unknown(type, payload):
            try container.encode(OpenAPIObjectContainer.unknown(type: type, payload: payload))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}
