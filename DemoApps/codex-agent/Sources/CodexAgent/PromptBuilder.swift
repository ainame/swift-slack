import Logging
import SlackKit

/// Seeds a Codex conversation with Slack history on the first turn seen by this process.
enum PromptBuilder {
    static func prepare(
        _ turn: AgentResponder.Turn,
        client: any APIProtocol,
        identity: BotIdentity?,
        logger: Logger,
    ) async -> String {
        if case let .thread(_, threadTs) = turn.session, turn.messageTs == threadTs {
            return turn.prompt
        }
        do {
            let messages = try await ConversationHistory.messages(in: turn.session, client: client)
            let origin = await originMessage(turn.origin, client: client, logger: logger)
            let transcript = ConversationHistory.transcript(
                of: messages,
                before: turn.isCommand ? nil : turn.messageTs,
                in: turn.session,
                origin: origin,
                identity: identity,
            )
            return (transcript ?? "") + turn.prompt
        } catch {
            logger.warning("Failed to read the conversation", metadata: ["session": "\(turn.session)", "error": "\(error)"])
            return turn.prompt
        }
    }

    private static func originMessage(_ link: MessageLink?, client: any APIProtocol, logger: Logger) async -> Message? {
        guard let link else { return nil }
        do {
            return try await ConversationHistory.message(at: link, client: client)
        } catch {
            // The app may not be able to read the channel the code channel was started from.
            logger.info("Could not read the code channel's origin", metadata: ["error": "\(error)"])
            return nil
        }
    }
}
