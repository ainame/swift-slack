import Logging
import SlackKit
import SlackStreaming

/// Runs the agent response loop from the Slack docs for one user message:
/// set the session to `processing`, stream tasks and text, then stop the stream with feedback buttons,
/// which returns the session to `active`.
actor AgentResponder {
    struct Turn: Sendable {
        let session: SessionKey
        let prompt: String
        let userId: String
        let teamId: String
    }

    private let backend: any AgentBackend
    private let logger: Logger
    /// The task producing chunks for each session's running turn. Cancelling it stops the turn.
    private var producers: [SessionKey: Task<Void, Never>] = [:]
    private var titledSessions: Set<SessionKey> = []

    init(backend: any AgentBackend, logger: Logger) {
        self.backend = backend
        self.logger = logger
    }

    func handle(_ turn: Turn, client: any APIProtocol) async {
        let session = turn.session
        guard producers[session] == nil else {
            await postBusyNotice(for: turn, client: client)
            return
        }

        await setProcessing(turn, client: client)

        // The agent's events go into an AsyncStream that ChatStream sends to Slack. The producer task is
        // separate so the stop button can cancel the agent while the message is still stopped properly.
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        producers[session] = Task {
            await self.produce(turn, into: continuation)
        }
        defer { producers[session] = nil }

        let transport = SlackChatStreamTransport(
            client: client,
            channel: session.channel,
            threadTs: session.threadTs,
            recipientUserId: turn.userId,
            recipientTeamId: turn.teamId,
        )
        do {
            try await ChatStream(transport: transport).send(chunks, blocks: Feedback.blocks())
        } catch {
            // The stop button ends the streaming message on Slack's side, so stopping it can fail here.
            // Leave `processing` anyway, or the session keeps spinning for an hour.
            logger.info("Could not finish the stream", metadata: ["session": "\(session)", "error": "\(error)"])
            producers[session]?.cancel()
            await setActive(session, client: client)
        }
    }

    /// Handles the stop button: interrupts the agent, and the running turn stops its message.
    func stop(_ session: SessionKey) async {
        guard let producer = producers[session] else { return }
        logger.info("Stopping turn", metadata: ["session": "\(session)"])
        await backend.interrupt(session)
        producer.cancel()
    }

    func titleChanged(_ session: SessionKey) {
        // The person named the session; stop proposing titles for it.
        titledSessions.insert(session)
    }

    private nonisolated func produce(_ turn: Turn, into continuation: AsyncStream<StreamChunk>.Continuation) async {
        defer { continuation.finish() }
        do {
            for try await event in backend.respond(to: turn.prompt, in: turn.session) {
                switch event {
                case let .task(task):
                    continuation.yield(.taskUpdate(task))
                case let .text(text):
                    continuation.yield(.markdownText(text))
                }
            }
            // Iterating a stream from a cancelled task ends it without an error.
            if Task.isCancelled {
                continuation.yield(.markdownText("\n\n_Stopped._"))
            }
        } catch {
            logger.error("Agent turn failed", metadata: ["session": "\(turn.session)", "error": "\(error)"])
            continuation.yield(.markdownText("\n\n:warning: Something went wrong: \(error)"))
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
