import Foundation
import Logging
import SlackKit

@main
struct CodexAgentApp {
    static let logger: Logger = {
        var logger = Logger(label: "codex-agent")
        logger.logLevel = .info
        return logger
    }()

    /// Prompts for a repository set with `CODEX_WORKSPACE`.
    static let workspacePrompts: [(title: String, message: String)] = [
        ("Explain this repository", "What does this repository do? Give me a short tour of its layout."),
        ("Find a function", "Where is the main entry point, and what does it do?"),
        ("Review recent changes", "Summarize the most recent commit and point out anything risky."),
    ]

    /// Prompts for the empty default workspace.
    static let generalPrompts: [(title: String, message: String)] = [
        ("Explain a concept", "Explain Swift's structured concurrency in a few short paragraphs."),
        ("Write a script", "Write a shell script that lists the ten largest files in a directory."),
        ("Debug an error", "What usually causes \"Sendable\" warnings in Swift 6, and how do I fix them?"),
    ]

    static func main() async {
        do {
            try await run()
        } catch {
            logger.error("Codex agent failed: \(error)")
            exit(1)
        }
    }

    private static func run() async throws {
        let environment = try await AgentConfiguration.load()
        let codex = try AgentConfiguration.makeCodex(from: environment, logger: logger)
        let isAllowed: @Sendable (String) -> Bool = { user in
            environment.allowedUserIds.isEmpty || environment.allowedUserIds.contains(user)
        }
        let questions = PendingQuestions()
        let responder = AgentResponder(codex: codex, questions: questions, logger: logger)
        let turns = TurnRouter(
            responder: responder,
            isAllowed: isAllowed,
            logger: logger,
        )
        let router = Router()

        // In the Agent messaging experience, app_home_opened with tab "messages" replaces
        // assistant_thread_started. Suggested prompts sit at the top of the Messages tab.
        router.onEvent(AppHomeOpenedEvent.self) { context, _, event in
            guard event.tab == "messages", let channel = event.channel else { return }
            let prompts = environment.workspace == nil ? generalPrompts : workspacePrompts
            try await setSuggestedPrompts(prompts, channel: channel, client: context.client)
        }

        // Direct messages to the agent, from the Messages tab or the split view, every message in a Slack Code
        // channel, and replies in channel threads the agent takes part in, so a conversation continues without
        // mentioning it each time. TurnRouter decides which of them to answer.
        router.onEvent(MessageEvent.self) { context, envelope, event in
            guard event.botId == nil,
                  let user = event.user,
                  let channel = event.channel,
                  let ts = event.ts,
                  let text = event.text, !text.isEmpty else {
                return
            }
            turns.start(IncomingMessage(
                source: .message,
                eventId: envelope.eventId,
                channel: channel,
                isDirectMessage: event.channelType == "im",
                ts: ts,
                threadTs: event.threadTs,
                userId: user,
                text: text,
                teamId: envelope.teamId,
            ), client: context.client)
        }

        // Mentions in channels; the reply goes into the mention's thread, or into a code channel's session.
        router.onEvent(AppMentionEvent.self) { context, envelope, event in
            guard event.botId == nil,
                  let user = event.user,
                  let channel = event.channel,
                  let ts = event.ts,
                  let text = event.text else {
                return
            }
            let prompt = text.replacing(/<@[A-Z0-9]+>\s*/, with: "")
            guard !prompt.isEmpty else { return }
            turns.start(IncomingMessage(
                source: .mention,
                eventId: envelope.eventId,
                channel: channel,
                isDirectMessage: false,
                ts: ts,
                threadTs: event.threadTs,
                userId: user,
                text: prompt,
                teamId: envelope.teamId,
            ), client: context.client)
        }

        // Subscribing to agent_session_stopped is what makes Slack show the stop button. A code channel's
        // session has no thread, and stopping it stops every turn in the channel, including messages still
        // being routed there.
        router.onEvent(AgentSessionStoppedEvent.self) { context, _, event in
            guard let channel = event.channel else {
                logger.warning("Stop event has no channel")
                return
            }
            logger.info("Received agent stop event", metadata: ["channel": "\(channel)", "thread_ts": "\(event.threadTs ?? "none")"])
            await turns.stop(channel: channel, threadTs: event.threadTs, client: context.client)
        }

        router.onEvent(AgentSessionTitleChangedEvent.self) { _, _, event in
            guard let channel = event.channel else { return }
            logger.info("Session renamed", metadata: ["title": "\(event.title ?? "")"])
            let session: SessionKey = if let threadTs = event.threadTs {
                .thread(channel: channel, threadTs: threadTs)
            } else {
                .codeChannel(channel: channel)
            }
            await responder.titleChanged(session)
        }

        Feedback.register(on: router, logger: logger)

        for command in ["/review", "/run"] {
            router.onSlashCommand(command) { context, payload in
                try await context.ack()
                let prompt = command == "/review" ? "Review the current changes. \(payload.text)" : payload.text
                guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                turns.start(.init(
                    source: .command, eventId: payload.triggerId, channel: payload.channelId, isDirectMessage: false,
                    ts: payload.triggerId, threadTs: nil, userId: payload.userId, text: prompt, teamId: payload.teamId,
                ), client: context.client)
            }
        }

        // Answers to the agent's ask_user tool, one action_id per option. Only the person asked can answer.
        for index in 0 ..< SlackUI.maxOptions {
            let actionId = SlackUI.choiceActionId(index)
            router.onAction(actionId) { context, payload in
                try await context.ack()
                guard let id = payload.blockActions.first(where: { $0.actionId == actionId })?.value,
                      let user = payload.user.id, isAllowed(user), let channel = payload.container.channelId else {
                    logger.warning("Ignored question button with missing fields or disallowed user", metadata: ["action_id": "\(actionId)"])
                    return
                }
                let answer = await questions.answer(id: id, index: index, userId: user)
                let result = switch answer {
                case .accepted: "accepted"
                case .notAsked: "wrong_user"
                case .expired: "expired"
                }
                logger.info("Question button handled", metadata: ["question_id": "\(id)", "result": "\(result)"])
                let notice: String? = switch answer {
                case .accepted: nil
                case let .notAsked(asked): "Only <@\(asked)> can answer this question."
                case .expired: "This question is no longer waiting for an answer."
                }
                if let notice {
                    _ = try await context.client.chatPostEphemeral(body: .json(.init(
                        channel: channel,
                        text: notice,
                        threadTs: payload.messageThreadTs,
                        user: user,
                    ))).ok.body.json.checked("chat.postEphemeral")
                }
            }
        }

        // Buttons on the cards from the agent's show_cards tool.
        router.onAction(SlackUI.openActionId) { context, _ in
            // Slack opens the link; the click still needs an acknowledgement.
            try await context.ack()
        }
        router.onAction(SlackUI.askActionId) { context, payload in
            try await context.ack()
            guard let question = payload.blockActions.first(where: { $0.actionId == SlackUI.askActionId })?.value,
                  let channel = payload.container.channelId,
                  let messageTs = payload.container.messageTs,
                  let user = payload.user.id, isAllowed(user),
                  let teamId = payload.team?.id else {
                return
            }
            turns.ask(.init(
                question: question,
                channel: channel,
                threadTs: payload.message?.threadTs,
                messageTs: messageTs,
                userId: user,
                teamId: teamId,
            ), client: context.client)
        }

        let app = try SlackApp(
            configuration: AgentConfiguration.configuration(from: environment),
            router: router,
            mode: AgentConfiguration.runtimeMode(from: environment),
        )
        logger.info("Starting Codex agent")
        try await app.run { slack in
            let response = try await slack.client.authTest().ok.body.json.checked("auth.test")
            guard let userId = response.userId else {
                throw SlackAPIError(method: "auth.test", code: "missing_user_id")
            }
            await responder.setIdentity(BotIdentity(userId: userId, botId: response.botId))
        }
    }

    private static func setSuggestedPrompts(
        _ prompts: [(title: String, message: String)],
        channel: String,
        client: any APIProtocol,
    ) async throws {
        // swift-slack types `prompts` as a string because slack-api-ref does; requests are form-encoded,
        // so it takes the JSON array as text.
        let objects = prompts.map { ["title": $0.title, "message": $0.message] }
        let json = try String(decoding: JSONSerialization.data(withJSONObject: objects), as: UTF8.self)
        _ = try await client.assistantThreadsSetSuggestedPrompts(body: .json(.init(
            channelId: channel,
            prompts: json,
            title: "What can I help with?",
        ))).ok.body.json.checked("assistant.threads.setSuggestedPrompts")
    }
}
