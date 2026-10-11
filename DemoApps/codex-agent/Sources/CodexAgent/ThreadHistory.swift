import SlackKit
import SlackStreaming

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

/// Reads a thread with `conversations.replies`, as the Slack docs suggest for thread context.
enum ThreadHistory {
    static func messages(in session: SessionKey, client: any APIProtocol) async throws -> [Message] {
        let response = try await client.conversationsReplies(body: .json(.init(
            channel: session.channel,
            limit: 100,
            ts: session.threadTs,
        ))).ok.body.json.checked("conversations.replies")
        return response.messages ?? []
    }

    /// Renders the thread before `messageTs` for a prompt, or `nil` when there is nothing before it.
    static func transcript(of messages: [Message], before messageTs: String, identity: BotIdentity?) -> String? {
        let lines = messages
            .filter { ($0.ts ?? "") < messageTs }
            .compactMap { message -> String? in
                guard let text = message.text, !text.isEmpty else { return nil }
                let author = identity?.isAuthor(of: message) == true ? "You" : "<@\(message.user ?? "unknown")>"
                return "\(author): \(text)"
            }
        guard !lines.isEmpty else { return nil }
        return """
        The conversation so far in this Slack thread, oldest first:

        \(lines.joined(separator: "\n\n"))

        The latest message, which you are answering:

        """
    }
}

extension Components.Schemas.ConversationsRepliesResponse: SlackResponse {}
extension Components.Schemas.AuthTestResponse: SlackResponse {}
