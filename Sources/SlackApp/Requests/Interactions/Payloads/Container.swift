import Foundation
import OpenAPIRuntime

public enum Container: Hashable, Sendable {
    public struct Message: Codable, Hashable, Sendable {
        public let messageTs: String
        public let channelId: String
        public let isEphemeral: Bool?

        public init(messageTs: String, channelId: String, isEphemeral: Bool?) {
            self.messageTs = messageTs
            self.channelId = channelId
            self.isEphemeral = isEphemeral
        }

        private enum CodingKeys: String, CodingKey {
            case messageTs = "message_ts"
            case channelId = "channel_id"
            case isEphemeral = "is_ephemeral"
        }
    }

    public struct MessageAttachment: Codable, Hashable, Sendable {
        public let messageTs: String
        public let channelId: String
        public let attachmentId: Int?
        public let isEphemeral: Bool?
        public let isAppUnfurl: Bool?
        public let appUnfurlUrl: String?
        public let threadTs: String?
        public let text: String?

        public init(
            messageTs: String,
            channelId: String,
            attachmentId: Int?,
            isEphemeral: Bool?,
            isAppUnfurl: Bool?,
            appUnfurlUrl: String?,
            threadTs: String?,
            text: String?,
        ) {
            self.messageTs = messageTs
            self.channelId = channelId
            self.attachmentId = attachmentId
            self.isEphemeral = isEphemeral
            self.isAppUnfurl = isAppUnfurl
            self.appUnfurlUrl = appUnfurlUrl
            self.threadTs = threadTs
            self.text = text
        }

        private enum CodingKeys: String, CodingKey {
            case messageTs = "message_ts"
            case channelId = "channel_id"
            case attachmentId = "attachment_id"
            case isEphemeral = "is_ephemeral"
            case isAppUnfurl = "is_app_unfurl"
            case appUnfurlUrl = "app_unfurl_url"
            case threadTs = "thread_ts"
            case text
        }
    }

    public struct View: Codable, Hashable, Sendable {
        public let viewId: String

        public init(viewId: String) {
            self.viewId = viewId
        }

        private enum CodingKeys: String, CodingKey {
            case viewId = "view_id"
        }
    }

    case message(Message)
    case messageAttachment(MessageAttachment)
    case view(View)
    case unknown(type: String, payload: OpenAPIObjectContainer)
}

extension Container {
    public var _type: String {
        switch self {
        case .message:
            "message"
        case .messageAttachment:
            "message_attachment"
        case .view:
            "view"
        case let .unknown(type, _):
            type
        }
    }

    public var viewId: String? {
        switch self {
        case let .view(value):
            value.viewId
        default:
            nil
        }
    }

    public var messageTs: String? {
        switch self {
        case let .message(value):
            value.messageTs
        case let .messageAttachment(value):
            value.messageTs
        case .view, .unknown:
            nil
        }
    }

    public var channelId: String? {
        switch self {
        case let .message(value):
            value.channelId
        case let .messageAttachment(value):
            value.channelId
        case .view, .unknown:
            nil
        }
    }

    public var attachmentId: Int? {
        switch self {
        case let .messageAttachment(value):
            value.attachmentId
        default:
            nil
        }
    }

    public var isEphemeral: Bool? {
        switch self {
        case let .message(value):
            value.isEphemeral
        case let .messageAttachment(value):
            value.isEphemeral
        case .view, .unknown:
            nil
        }
    }

    public init(viewId: String) {
        self = .view(.init(viewId: viewId))
    }
}

extension Container: Codable {
    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case messageTs = "message_ts"
        case channelId = "channel_id"
        case attachmentId = "attachment_id"
        case viewId = "view_id"
        case isEphemeral = "is_ephemeral"
        case isAppUnfurl = "is_app_unfurl"
        case appUnfurlUrl = "app_unfurl_url"
        case threadTs = "thread_ts"
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: ._type)

        switch type {
        case "message":
            self = try .message(.init(from: decoder))
        case "message_attachment":
            self = try .messageAttachment(.init(from: decoder))
        case "view":
            self = try .view(.init(from: decoder))
        default:
            self = try .unknown(type: type, payload: .init(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .message(value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("message", forKey: ._type)
            try container.encode(value.messageTs, forKey: .messageTs)
            try container.encode(value.channelId, forKey: .channelId)
            try container.encodeIfPresent(value.isEphemeral, forKey: .isEphemeral)
        case let .messageAttachment(value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("message_attachment", forKey: ._type)
            try container.encode(value.messageTs, forKey: .messageTs)
            try container.encode(value.channelId, forKey: .channelId)
            try container.encodeIfPresent(value.attachmentId, forKey: .attachmentId)
            try container.encodeIfPresent(value.isEphemeral, forKey: .isEphemeral)
            try container.encodeIfPresent(value.isAppUnfurl, forKey: .isAppUnfurl)
            try container.encodeIfPresent(value.appUnfurlUrl, forKey: .appUnfurlUrl)
            try container.encodeIfPresent(value.threadTs, forKey: .threadTs)
            try container.encodeIfPresent(value.text, forKey: .text)
        case let .view(value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("view", forKey: ._type)
            try container.encode(value.viewId, forKey: .viewId)
        case let .unknown(type, payload):
            var mergedValue = payload.value
            mergedValue["type"] = type
            try OpenAPIObjectContainer(unvalidatedValue: mergedValue).encode(to: encoder)
        }
    }
}
