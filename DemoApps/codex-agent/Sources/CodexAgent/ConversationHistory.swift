import SlackKit

/// The app's own bot user, from `auth.test`.
struct BotIdentity: Sendable {
    let userId: String
    let botId: String?

    /// Whether `text` mentions the bot, which also delivers an `app_mention` event.
    func isMentioned(in text: String) -> Bool {
        text.contains("<@\(userId)>")
    }

    func isAuthor(of message: Message) -> Bool {
        message.user == userId || (botId != nil && message.botId == botId)
    }
}

/// A message elsewhere in Slack, such as the one a code channel was started from.
struct MessageLink: Hashable, Sendable {
    let channel: String
    let ts: String
}

/// Reads a session's conversation: a thread with `conversations.replies`, as the Slack docs suggest for thread
/// context, and a code channel with `conversations.history` plus each message's thread replies.
/// Both return the oldest message first.
enum ConversationHistory {
    static func messages(in session: SessionKey, client: any APIProtocol) async throws -> [Message] {
        switch session {
        case let .thread(channel, threadTs):
            return try await replies(channel: channel, threadTs: threadTs, client: client)
        case let .codeChannel(channel):
            let parents = try await channelMessages(channel: channel, limit: 100, client: client)
            var messages = parents
            for parent in parents where (parent.replyCount ?? 0) > 0 {
                guard let ts = parent.ts else { continue }
                var cursor: String?
                repeat {
                    try Task.checkCancellation()
                    let response = try await client.conversationsReplies(body: .json(.init(
                        channel: channel, cursor: cursor, limit: 100, ts: ts,
                    ))).ok.body.json.checked("conversations.replies")
                    // Replies includes the parent again; keep the history copy only once.
                    messages.append(contentsOf: (response.messages ?? []).filter { $0.ts != ts })
                    cursor = response.responseMetadata?.nextCursor
                } while cursor?.isEmpty == false
            }
            return messages.sorted { ($0.ts ?? "") < ($1.ts ?? "") }
        }
    }

    static func replies(channel: String, threadTs: String, client: any APIProtocol) async throws -> [Message] {
        let response = try await client.conversationsReplies(body: .json(.init(
            channel: channel,
            limit: 100,
            ts: threadTs,
        ))).ok.body.json.checked("conversations.replies")
        return response.messages ?? []
    }

    /// The channel's latest top-level messages, oldest first; `conversations.history` returns newest first.
    static func channelMessages(channel: String, limit: Int, client: any APIProtocol) async throws -> [Message] {
        let response = try await client.conversationsHistory(body: .json(.init(
            channel: channel,
            limit: Double(limit),
        ))).ok.body.json.checked("conversations.history")
        return (response.messages ?? []).reversed()
    }

    /// The top-level message at `link`, or `nil` when the channel does not have one there.
    static func message(at link: MessageLink, client: any APIProtocol) async throws -> Message? {
        let response = try await client.conversationsHistory(body: .json(.init(
            channel: link.channel,
            inclusive: true,
            latest: link.ts,
            limit: 1,
        ))).ok.body.json.checked("conversations.history")
        return response.messages?.first { $0.ts == link.ts }
    }

    /// Renders the conversation before `messageTs` for a prompt, or `nil` when there is nothing to show.
    /// `origin` is the message a code channel was started from.
    static func transcript(
        of messages: [Message],
        before messageTs: String?,
        in session: SessionKey,
        origin: Message? = nil,
        identity: BotIdentity?,
    ) -> String? {
        let lines = messages
            .filter { message in
                guard let messageTs else { return true }
                return (message.ts ?? "") < messageTs
            }
            .compactMap { line(for: $0, identity: identity) }
        let originLine = origin.flatMap { line(for: $0, identity: identity) }
        guard !lines.isEmpty || originLine != nil else { return nil }

        var sections: [String] = []
        if let originLine {
            sections.append("This Slack channel was started from this message:\n\n\(originLine)")
        }
        if !lines.isEmpty {
            let place = switch session {
            case .thread: "this Slack thread"
            case .codeChannel: "this Slack channel"
            }
            sections.append("The conversation so far in \(place), oldest first:\n\n\(lines.joined(separator: "\n\n"))")
        }
        return sections.joined(separator: "\n\n") + "\n\nThe latest message, which you are answering:\n\n"
    }

    static func line(for message: Message, identity: BotIdentity?) -> String? {
        guard let text = message.text, !text.isEmpty else { return nil }
        let author = identity?.isAuthor(of: message) == true ? "You" : "<@\(message.user ?? "unknown")>"
        return "\(author): \(text)"
    }
}

extension Components.Schemas.ConversationsRepliesResponse: SlackResponse {}
extension Components.Schemas.ConversationsHistoryResponse: SlackResponse {}
extension Components.Schemas.AuthTestResponse: SlackResponse {}
extension Components.Schemas.ChatPostMessageResponse: SlackResponse {}
