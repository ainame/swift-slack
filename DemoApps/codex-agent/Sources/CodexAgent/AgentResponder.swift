import Logging
import SlackKit

/// Runs the agent response loop from the Slack docs for one user message:
/// set the session to `processing`, stream tasks and text, then stop the stream with feedback buttons,
/// which returns the session to `active`.
actor AgentResponder {
    struct Turn: Sendable {
        let session: SessionKey
        /// The `ts` of the message being answered. It equals `session.threadTs` for a thread's first message.
        let messageTs: String
        let prompt: String
        let userId: String
        let teamId: String
    }

    private let backend: any AgentBackend
    private let questions: PendingQuestions
    private let logger: Logger
    /// Stop controls for the structured producer scopes of the running turns.
    private var producers: [SessionKey: TurnProducer] = [:]
    private var titledSessions: Set<SessionKey> = []
    /// Sessions the person renamed, whose title the agent leaves alone.
    private var userTitledSessions: Set<SessionKey> = []
    /// Sessions this process has answered in, whose backend already holds the conversation.
    private var engagedSessions: Set<SessionKey> = []
    private var identity: BotIdentity?

    init(backend: any AgentBackend, questions: PendingQuestions, logger: Logger) {
        self.backend = backend
        self.questions = questions
        self.logger = logger
    }

    func setIdentity(_ identity: BotIdentity) {
        self.identity = identity
    }

    /// Whether to answer a channel thread reply that does not mention the bot: only in threads the agent
    /// already takes part in. After a restart, the thread itself shows whether the bot has replied there.
    func shouldAnswerThreadReply(text: String, in session: SessionKey, client: any APIProtocol) async -> Bool {
        // A reply that mentions the bot also arrives as app_mention, which answers it.
        if identity?.isMentioned(in: text) == true {
            return false
        }
        if engagedSessions.contains(session) {
            return true
        }
        guard let identity else { return false }
        do {
            return try await ThreadHistory.messages(in: session, client: client).contains(where: identity.isAuthor)
        } catch {
            logger.warning("Failed to read the thread", metadata: ["session": "\(session)", "error": "\(error)"])
            return false
        }
    }

    func handle(_ turn: Turn, client: any APIProtocol) async {
        let session = turn.session
        guard producers[session] == nil else {
            await postBusyNotice(for: turn, client: client)
            return
        }

        // The agent's events go into an AsyncStream that streamMessage sends to Slack. Only the producer
        // scope is stopped by the button, so Slack delivery can drain and finish the message.
        // It is registered before the first `await`: the actor takes other calls while this one waits,
        // and a second message in the same thread must find the session busy.
        let (parts, continuation) = AsyncStream.makeStream(of: StreamingMessage.Part.self)
        let tools = SlackAgentTools(
            client: client,
            session: session,
            userId: turn.userId,
            identity: identity,
            questions: questions,
            isTitledByUser: { [weak self] in await self?.isTitledByUser(session) ?? true },
        )
        let producer = TurnProducer()
        producers[session] = producer
        defer { producers[session] = nil }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await producer.run {
                    if !Task.isCancelled {
                        await self.setProcessing(turn, client: client)
                    }
                    let prompt = if Task.isCancelled {
                        turn.prompt
                    } else {
                        await self.prompt(for: turn, client: client)
                    }
                    await self.produce(turn, prompt: prompt, tools: tools, into: continuation)
                }
            }
            // A failed Slack delivery must also stop and join the producer before clearing the session.
            defer { group.cancelAll() }

            do {
                _ = try await client.streamMessage(
                    parts,
                    channel: session.channel,
                    threadTs: session.threadTs,
                    recipient: .init(userId: turn.userId, teamId: turn.teamId),
                    blocks: Feedback.blocks(),
                )
            } catch {
                // The stop button ends the streaming message on Slack's side, so stopping it can fail here.
                // Leave `processing` anyway, or the session keeps spinning for an hour.
                logger.info("Could not finish the stream", metadata: ["session": "\(session)", "error": "\(error)"])
                await questions.cancel(session)
                producer.stop()
                await setActive(session, client: client)
            }
        }
    }

    /// Handles the stop button: interrupts the agent, and the running turn stops its message.
    func stop(_ session: SessionKey) async {
        guard let producer = producers[session] else { return }
        logger.info("Stopping turn", metadata: ["session": "\(session)"])
        // A question waiting for a click holds Codex's message loop, so end it before interrupting.
        await questions.cancel(session)
        // Cancelling the producer ends its iteration of the backend's stream, which stops the turn.
        producer.stop()
    }

    func titleChanged(_ session: SessionKey) {
        // The person named the session; stop proposing titles for it.
        titledSessions.insert(session)
        userTitledSessions.insert(session)
    }

    private func isTitledByUser(_ session: SessionKey) -> Bool {
        userTitledSessions.contains(session)
    }

    /// The backend keeps a session's conversation, but not one it has not seen: a mention in the middle of
    /// a thread, or a thread from before a restart. Then the prompt starts with the thread so far.
    private func prompt(for turn: Turn, client: any APIProtocol) async -> String {
        guard engagedSessions.insert(turn.session).inserted, turn.messageTs != turn.session.threadTs else {
            return turn.prompt
        }
        do {
            let messages = try await ThreadHistory.messages(in: turn.session, client: client)
            let transcript = ThreadHistory.transcript(of: messages, before: turn.messageTs, identity: identity)
            return (transcript ?? "") + turn.prompt
        } catch {
            logger.warning("Failed to read the thread", metadata: ["session": "\(turn.session)", "error": "\(error)"])
            return turn.prompt
        }
    }

    /// Streams the backend's events and finishes with the cards the agent asked for.
    private nonisolated func produce(
        _ turn: Turn,
        prompt: String,
        tools: any AgentTools,
        into continuation: AsyncStream<StreamingMessage.Part>.Continuation,
    ) async {
        var cards: [SlackUI.Card] = []
        defer {
            if !Task.isCancelled, !cards.isEmpty {
                continuation.yield(.blocks(SlackUI(cards: cards).blocks()))
            }
            continuation.finish()
        }
        do {
            try Task.checkCancellation()
            for try await event in backend.respond(to: prompt, in: turn.session, tools: tools) {
                switch event {
                case let .task(task):
                    continuation.yield(.task(task))
                case let .text(text):
                    continuation.yield(.markdown(text))
                case let .cards(ui):
                    cards += ui.cards
                }
            }
        } catch {
            if !Task.isCancelled {
                logger.error("Agent turn failed", metadata: ["session": "\(turn.session)", "error": "\(error)"])
                continuation.yield(.markdown("\n\n:warning: Something went wrong: \(error)"))
            }
        }
        // Cancellation can end iteration normally or throw from the backend.
        if Task.isCancelled {
            continuation.yield(.markdown("\n\n_Stopped._"))
        }
    }

    private func setProcessing(_ turn: Turn, client: any APIProtocol) async {
        let session = turn.session
        let title = titledSessions.insert(session).inserted ? Self.title(for: turn.prompt) : nil
        do {
            // The title and initiator only apply when this call creates the session.
            _ = try await client.agentsSessionsSetStatus(body: .json(.init(
                channelId: session.channel,
                status: "processing",
                threadTs: session.threadTs,
                title: title,
                initiatorUserId: turn.userId,
            ))).ok.body.json.checked("agents.sessions.setStatus")
        } catch {
            logger.warning("Failed to set the session to processing", metadata: ["error": "\(error)"])
        }
    }

    private func setActive(_ session: SessionKey, client: any APIProtocol) async {
        do {
            _ = try await client.agentsSessionsSetStatus(body: .json(.init(
                channelId: session.channel,
                status: "active",
                threadTs: session.threadTs,
            ))).ok.body.json.checked("agents.sessions.setStatus")
        } catch {
            logger.error("Failed to set the session to active", metadata: ["error": "\(error)"])
        }
    }

    private func postBusyNotice(for turn: Turn, client: any APIProtocol) async {
        do {
            _ = try await client.chatPostEphemeral(body: .json(.init(
                channel: turn.session.channel,
                text: "I'm still working on your previous message. Press stop to start over.",
                threadTs: turn.session.threadTs,
                user: turn.userId,
            ))).ok.body.json.checked("chat.postEphemeral")
        } catch {
            logger.warning("Failed to post the busy notice", metadata: ["error": "\(error)"])
        }
    }

    /// Uses the first line of the first prompt as the session title (Slack allows up to 200 characters).
    static func title(for prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return line.count > 60 ? line.prefix(59) + "…" : line
    }
}
