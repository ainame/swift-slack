import Logging
import SlackKit

/// Runs the agent response loop from the Slack docs for one user message:
/// set the session to `processing`, stream tasks and text, then stop the stream with feedback buttons,
/// which returns the session to `active`.
actor AgentResponder {
    struct Turn: Sendable, Equatable {
        let session: SessionKey
        /// The thread the reply goes into, or `nil` for a top-level reply in a code channel. A thread reply in a
        /// code channel is answered in its thread but belongs to the channel's session.
        let replyThreadTs: String?
        /// The `ts` of the message being answered. It equals the thread's `ts` for a thread's first message.
        let messageTs: String
        let prompt: String
        let userId: String
        let teamId: String
        /// The message a code channel was started from, shown to the agent with the channel's history.
        var origin: MessageLink?
    }

    /// A turn being answered, registered before its first `await` so that a stop can always find it.
    private struct RunningTurn {
        let replyThreadTs: String?
        let producer: TurnProducer
        let parts: AsyncThrowingStream<StreamingMessage.Part, any Error>.Continuation
    }

    private let backend: any AgentBackend
    private let questions: PendingQuestions
    private let logger: Logger
    private let lifecycle = CodeChannelLifecycle()
    private var running: [SessionKey: RunningTurn] = [:]
    private var titledSessions: Set<SessionKey> = []
    /// Sessions the person renamed, whose title the agent leaves alone.
    private var userTitledSessions: Set<SessionKey> = []
    /// Sessions this process has answered in, whose backend already holds the conversation.
    private var engagedSessions: Set<SessionKey> = []
    private(set) var identity: BotIdentity?

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
    func shouldAnswerThreadReply(in session: SessionKey, client: any APIProtocol) async -> Bool {
        if engagedSessions.contains(session) {
            return true
        }
        guard let identity else { return false }
        do {
            return try await ConversationHistory.messages(in: session, client: client).contains(where: identity.isAuthor)
        } catch {
            logger.warning("Failed to read the thread", metadata: ["session": "\(session)", "error": "\(error)"])
            return false
        }
    }

    /// Answers `turn`. `attempt` is the routing that produced it: a stop that discarded it ends the turn here,
    /// checked together with the registration below so that a stop either finds the turn running or the attempt
    /// discarded.
    func handle(_ turn: Turn, client: any APIProtocol, attempt: RoutingAttempts.Attempt? = nil, parent: TurnProducer? = nil) async {
        guard parent?.isSessionStopped != true else { return }
        let session = turn.session
        guard attempt?.isCancelled != true else { return }
        guard running[session] == nil else {
            await postBusyNotice(for: turn, client: client)
            return
        }

        // The agent's events go into a stream that streamMessage sends to Slack. A local cancellation stops
        // only the producer scope, so Slack delivery can drain and finish the message. A stop from Slack ends
        // the stream with SessionStopped instead, and nothing more goes to Slack.
        // The turn is registered before the first `await`: the actor takes other calls while this one waits,
        // a second message in the same session must find it busy, and an early stop must find the turn.
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: StreamingMessage.Part.self)
        let producer = TurnProducer()
        running[session] = RunningTurn(replyThreadTs: turn.replyThreadTs, producer: producer, parts: continuation)
        defer { running[session] = nil }
        let tools = SlackAgentTools(
            client: client,
            session: session,
            replyThreadTs: turn.replyThreadTs,
            userId: turn.userId,
            identity: identity,
            questions: questions,
            isTitledByUser: { [weak self] in await self?.isTitledByUser(session) ?? true },
            producer: producer,
            lifecycle: lifecycle,
            messageTs: turn.messageTs,
            logger: logger,
            onCodeChannel: { [weak self] channel in
                guard !producer.isSessionStopped else { return }
                Task {
                    await self?.handle(.init(
                        session: .codeChannel(channel: channel), replyThreadTs: nil,
                        messageTs: turn.messageTs, prompt: turn.prompt, userId: turn.userId, teamId: turn.teamId,
                        origin: .init(channel: turn.session.channel, ts: turn.messageTs),
                    ), client: client, parent: producer)
                }
            },
            endSession: { [weak self] in await self?.stop(channel: session.channel, threadTs: nil) },
        )

        var deliveryFailed = false
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await producer.run {
                    if !Task.isCancelled {
                        await self.setProcessing(turn, producer: producer, client: client)
                    }
                    let prompt = if Task.isCancelled || producer.reason != nil {
                        turn.prompt
                    } else {
                        await self.prompt(for: turn, client: client)
                    }
                    await self.produce(turn, prompt: prompt, tools: tools, producer: producer, into: continuation)
                }
            }
            // Delivery ending, for any reason, stops and joins the producer before the session is cleared.
            defer { group.cancelAll() }

            do {
                _ = try await client.streamMessage(
                    parts,
                    channel: session.channel,
                    threadTs: turn.replyThreadTs,
                    recipient: .init(userId: turn.userId, teamId: turn.teamId),
                    blocks: Feedback.blocks(),
                )
            } catch is StreamingMessage.SessionStopped {
                logger.info("Slack stopped the session", metadata: ["session": "\(session)"])
            } catch {
                logger.info("Could not finish the stream", metadata: ["session": "\(session)", "error": "\(error)"])
                deliveryFailed = true
                await questions.cancel(session)
                producer.cancel()
            }
        }
        // A failed delivery leaves the session `processing`, which spins for an hour, so set it back. Slack has
        // already ended a stopped session.
        if deliveryFailed, !producer.isSessionStopped {
            await setActive(session, client: client)
        }
    }

    /// Handles Slack's `agent_session_stopped`. Without `threadTs`, every turn in the channel stops, including
    /// the thread sessions in it. With `threadTs`, the turn of that thread's session stops, or the turn replying
    /// in that thread of a code channel.
    func stop(channel: String, threadTs: String?) async {
        let stopped = running.filter { session, turn in
            guard session.channel == channel else { return false }
            guard let threadTs else { return true }
            return session.threadTs == threadTs || turn.replyThreadTs == threadTs
        }
        for (session, turn) in stopped {
            logger.info("Stopping turn", metadata: ["session": "\(session)"])
            // Slack has ended the stream: streamMessage drops what it has not sent and makes no more calls.
            turn.parts.finish(throwing: StreamingMessage.SessionStopped())
            // Cancelling the producer ends its iteration of the backend's stream, which stops the turn. The
            // tools see the stop before their question ends below, so they leave Slack alone.
            turn.producer.stopSession()
        }
        // A question waiting for a click holds Codex's message loop, so end it to let the interrupt through.
        for session in stopped.keys {
            await questions.cancel(session)
        }
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
    /// a thread, a code channel with earlier messages, or a conversation from before a restart. Then the prompt
    /// starts with the conversation so far.
    private func prompt(for turn: Turn, client: any APIProtocol) async -> String {
        guard engagedSessions.insert(turn.session).inserted else {
            return turn.prompt
        }
        if case let .thread(_, threadTs) = turn.session, turn.messageTs == threadTs {
            return turn.prompt
        }
        do {
            let messages = try await ConversationHistory.messages(in: turn.session, client: client)
            let origin = await originMessage(turn.origin, client: client)
            let transcript = ConversationHistory.transcript(
                of: messages,
                before: turn.messageTs,
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

    private func originMessage(_ link: MessageLink?, client: any APIProtocol) async -> Message? {
        guard let link else { return nil }
        do {
            return try await ConversationHistory.message(at: link, client: client)
        } catch {
            // The app may not be able to read the channel the code channel was started from.
            logger.info("Could not read the code channel's origin", metadata: ["error": "\(error)"])
            return nil
        }
    }

    /// Streams the backend's events and finishes with the cards the agent asked for.
    private nonisolated func produce(
        _ turn: Turn,
        prompt: String,
        tools: any AgentTools,
        producer: TurnProducer,
        into continuation: AsyncThrowingStream<StreamingMessage.Part, any Error>.Continuation,
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
                case let .diff(diff):
                    if case .codeChannel = turn.session, !producer.isSessionStopped {
                        do { try await tools.publishView(.diff(content: diff)) }
                        catch {
                            if !producer.isSessionStopped {
                                logger.warning("Could not publish diff", metadata: ["error": "\(error)"])
                            }
                        }
                    }
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
        // Cancellation can end iteration normally or throw from the backend. A message the app stops itself
        // says so; a session that Slack stopped takes nothing more.
        if Task.isCancelled, !producer.isSessionStopped {
            continuation.yield(.markdown("\n\n_Stopped._"))
        }
    }

    private func setProcessing(_ turn: Turn, producer: TurnProducer, client: any APIProtocol) async {
        // Checked on the actor, which also runs `stop`, so no call starts after a stop is recorded.
        guard producer.reason == nil else { return }
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
        // Everyone in a code channel shares its session, so the running turn may answer someone else.
        let text = switch turn.session {
        case .thread: "I'm still working on your previous message. Press stop to start over."
        case .codeChannel: "I'm still working on an earlier message in this channel. Press stop to start over."
        }
        do {
            _ = try await client.chatPostEphemeral(body: .json(.init(
                channel: turn.session.channel,
                text: text,
                threadTs: turn.replyThreadTs,
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
