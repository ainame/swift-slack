import Foundation
import Logging
import OpenAPIRuntime
import SlackBlockKit
import SlackClient
import SlackClient

public struct Say: Sendable {
    private let client: any APIProtocol
    private let logger: Logger

    package init(client: any APIProtocol, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    @discardableResult
    public func callAsFunction(
        text: String = "",
        channel: String,
        blocks: [Block]? = nil,
        attachments: [Attachment]? = nil,
        replyBroadcast: Bool? = nil,
        threadTs: String? = nil,
        markdownText: String? = nil,
        mrkdwn: Bool? = nil,
        parse: Payload.Parse? = nil,
        linkNames: Bool? = nil,
        username: String? = nil,
        iconEmoji: String? = nil,
        iconUrl: String? = nil,
        unfurlLinks: Bool? = nil,
        unfurlMedia: Bool? = nil,
        metadata: OpenAPIObjectContainer? = nil,
    ) async throws -> Bool {
        try await callAsFunction(
            Payload(
                channel: channel,
                text: text,
                blocks: blocks,
                attachments: attachments,
                threadTs: threadTs,
                replyBroadcast: replyBroadcast,
                markdownText: markdownText,
                mrkdwn: mrkdwn,
                parse: parse,
                linkNames: linkNames,
                username: username,
                iconEmoji: iconEmoji,
                iconUrl: iconUrl,
                unfurlLinks: unfurlLinks,
                unfurlMedia: unfurlMedia,
                metadata: metadata,
            ),
        )
    }

    @discardableResult
    public func callAsFunction(
        _ payload: Payload,
    ) async throws -> Bool {
        #if WebAPI_Chat
        let result = try await client.chatPostMessage(
            body: .json(payload.asInput()),
        )
        return try result.ok.body.json.ok
        #else
        logger.error("say() method failed. WebAPI_Chat trait is not enabled.")
        return false
        #endif
    }
}

extension Say {
    public struct Payload {
        public enum Parse: String {
            case none
            case full
        }

        public var channel: String
        public var text: String
        public var blocks: [Block]?
        public var attachments: [Attachment]?
        public var threadTs: String?
        public var username: String?
        public var iconEmoji: String?
        public var iconUrl: String?
        public var linkNames: Bool?
        public var markdownText: String?
        public var mrkdwn: Bool?
        public var parse: Parse?
        public var replyBroadcast: Bool?
        public var unfurlLinks: Bool?
        public var unfurlMedia: Bool?
        public var metadata: OpenAPIObjectContainer?

        public init(
            channel: String,
            text: String = "",
            blocks: [Block]? = nil,
            attachments: [Attachment]? = nil,
            threadTs: String? = nil,
            replyBroadcast: Bool? = nil,
            markdownText: String? = nil,
            mrkdwn: Bool? = nil,
            parse: Parse? = nil,
            linkNames: Bool? = nil,
            username: String? = nil,
            iconEmoji: String? = nil,
            iconUrl: String? = nil,
            unfurlLinks: Bool? = nil,
            unfurlMedia: Bool? = nil,
            metadata: OpenAPIObjectContainer? = nil,
        ) {
            self.channel = channel
            self.text = text
            self.blocks = blocks
            self.attachments = attachments
            self.threadTs = threadTs
            self.replyBroadcast = replyBroadcast
            self.markdownText = markdownText
            self.mrkdwn = mrkdwn
            self.parse = parse
            self.linkNames = linkNames
            self.username = username
            self.iconUrl = iconUrl
            self.iconEmoji = iconEmoji
            self.unfurlLinks = unfurlLinks
            self.unfurlMedia = unfurlMedia
            self.metadata = metadata
        }

        private enum CodingKeys: String, CodingKey {
            case channel
            case text
            case blocks
            case attachments
            case threadTs = "thread_ts"
            case replyBroadcast = "reply_broadcast"
            case markdownText = "mrkdwn_text"
            case mrkdwn
            case parse
            case iconEmoji = "icon_emoji"
            case iconUrl = "icon_url"
            case linkNames = "link_names"
            case username
            case unfurlLinks = "unfurl_links"
            case unfurlMedia = "unfurl_media"
            case metadata
        }

        #if WebAPI_Chat
        fileprivate func asInput() -> Operations.ChatPostMessage.Input.Body.JsonPayload {
            var payload = Operations.ChatPostMessage.Input.Body.JsonPayload(channel: channel)
            payload.text = text
            payload.asUser = nil
            payload.iconEmoji = iconEmoji
            payload.iconUrl = iconUrl
            payload.linkNames = linkNames
            payload.markdownText = markdownText
            payload.mrkdwn = mrkdwn
            payload.parse = parse.flatMap { $0 == .none ? "none" : "full" }
            payload.replyBroadcast = replyBroadcast
            payload.threadTs = threadTs
            payload.unfurlLinks = unfurlLinks
            payload.unfurlMedia = unfurlMedia
            payload.username = username
            payload.blocks = blocks
            payload.attachments = attachments
            payload.metadata = metadata
            return payload
        }
        #endif
    }
}
