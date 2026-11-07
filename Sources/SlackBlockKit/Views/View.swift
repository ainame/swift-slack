import OpenAPIRuntime

public enum View: Codable, Hashable, Sendable {
    case modal(ModalView)
    case homeTab(HomeTabView)
    case unknown(type: String, payload: OpenAPIObjectContainer)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let typeContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try typeContainer.decode(String.self, forKey: .type)

        switch type {
        case "modal":
            self = try .modal(container.decode(ModalView.self))
        case "home":
            self = try .homeTab(container.decode(HomeTabView.self))
        default:
            self = try .unknown(type: type, payload: OpenAPIObjectContainer(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .modal(view):
            try container.encode(view)
        case let .homeTab(view):
            try container.encode(view)
        case let .unknown(type, payload):
            try container.encode(OpenAPIObjectContainer.unknown(type: type, payload: payload))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public var callbackId: String? {
        switch self {
        case let .modal(view):
            view.callbackId
        case let .homeTab(view):
            view.callbackId
        case let .unknown(_, payload):
            payload.string(forKey: "callback_id")
        }
    }

    public var privateMetadata: String? {
        switch self {
        case let .modal(view):
            view.privateMetadata
        case let .homeTab(view):
            view.privateMetadata
        case let .unknown(_, payload):
            payload.string(forKey: "private_metadata")
        }
    }

    public var id: String? {
        switch self {
        case let .modal(view):
            view.id
        case let .homeTab(view):
            view.id
        case let .unknown(_, payload):
            payload.string(forKey: "id")
        }
    }

    public var hash: String? {
        switch self {
        case let .modal(view):
            view.hash
        case let .homeTab(view):
            view.hash
        case let .unknown(_, payload):
            payload.string(forKey: "hash")
        }
    }

    public var state: StateValuesObject? {
        switch self {
        case let .modal(view):
            view.state
        case let .homeTab(view):
            view.state
        case .unknown:
            nil
        }
    }
}
