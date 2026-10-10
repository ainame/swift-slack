import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime
import SlackBlockKit
import SlackClient
import SlackClient

public struct Respond: Sendable {
    private let transport: any ClientTransport
    private let logger: Logger
    private let jsonEncoder = JSONEncoder()

    package init(transport: any ClientTransport, logger: Logger) {
        self.transport = transport
        self.logger = logger
    }

    @discardableResult
    public func callAsFunction(to url: URL, text: String, responseType: Payload.ResponseType? = nil) async throws -> Bool {
        let payload = Payload(text: text, responseType: responseType)
        return try await callAsFunction(to: url, payload: payload)
    }

    @discardableResult
    public func callAsFunction(
        to url: URL,
        text: String = "",
        blocks: [Block]? = nil,
        attachments: [Attachment]? = nil,
        responseType: Payload.ResponseType? = nil,
        replaceOriginal: Bool? = nil,
        deleteOriginal: Bool? = nil,
        unfurlLinks: Bool? = nil,
        unfurlMedia: Bool? = nil,
        threadTs: String? = nil,
        metadata: OpenAPIObjectContainer? = nil,
    ) async throws -> Bool {
        let payload = Payload(
            text: text,
            blocks: blocks,
            attachments: attachments,
            responseType: responseType,
            replaceOriginal: replaceOriginal,
            deleteOriginal: deleteOriginal,
            unfurlLinks: unfurlLinks,
            unfurlMedia: unfurlMedia,
            threadTs: threadTs,
            metadata: metadata,
        )
        return try await callAsFunction(to: url, payload: payload)
    }

    @discardableResult
    public func callAsFunction(to url: URL, payload: Payload) async throws -> Bool {
        let data = try jsonEncoder.encode(payload)
        let (response, _) = try await transport.send(
            HTTPRequest(
                method: .post,
                scheme: "https",
                authority: nil,
                path: url.path(),
                headerFields: HTTPFields([HTTPField(name: .contentType, value: "application/json")]),
            ),
            body: HTTPBody(data),
            baseURL: url.host.flatMap { URL(string: "https://\($0)") } ?? URL(string: "https://hooks.slack.com")!,
            operationID: "response_url",
        )
        return response.status.code == 200
    }
}

extension Respond {
    public struct Payload: Encodable {
        public enum ResponseType: String, Encodable {
            case inChannel = "in_channel"
            case ephemeral
        }

        public var text: String
        public var channel: String?
        public var blocks: [Block]?
        public var attachments: [Attachment]?
        public var responseType: ResponseType?
        public var replaceOriginal: Bool?
        public var deleteOriginal: Bool?
        public var unfurlLinks: Bool?
        public var unfurlMedia: Bool?
        public var threadTs: String?
        public var metadata: OpenAPIObjectContainer?

        public init(
            text: String = "",
            blocks: [Block]? = nil,
            attachments: [Attachment]? = nil,
            responseType: ResponseType? = nil,
            replaceOriginal: Bool? = nil,
            deleteOriginal: Bool? = nil,
            unfurlLinks: Bool? = nil,
            unfurlMedia: Bool? = nil,
            threadTs: String? = nil,
            metadata: OpenAPIObjectContainer? = nil,
        ) {
            self.text = text
            self.blocks = blocks
            self.attachments = attachments
            self.responseType = responseType
            self.replaceOriginal = replaceOriginal
            self.deleteOriginal = deleteOriginal
            self.unfurlLinks = unfurlLinks
            self.unfurlMedia = unfurlMedia
            self.threadTs = threadTs
            self.metadata = metadata
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case blocks
            case attachments
            case responseType = "response_type"
            case replaceOriginal = "replace_original"
            case deleteOriginal = "delete_original"
            case unfurlLinks = "unfurl_links"
            case unfurlMedia = "unfurl_media"
            case threadTs = "thread_ts"
            case metadata
        }
    }
}
