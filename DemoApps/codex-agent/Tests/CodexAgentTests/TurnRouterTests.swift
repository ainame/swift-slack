@testable import CodexAgent
import Logging
import SlackKit
import Testing

struct TurnRouterTests {
    let slack = FakeSlack()
    let backend = ScriptedBackend()
    let responder: AgentResponder

    init() {
        responder = AgentResponder(backend: backend, questions: PendingQuestions(), logger: Logger(label: "test"))
    }

    @Test
    func `commands use channel sessions and never answer in ordinary channels`() async {
        let client = await slack.client()
        await slack.channel(recordType: nil)
        #expect(await router().route(message("command-1", source: .command, ts: "trigger-1"), client: client) == nil)
        await slack.channel(recordType: "agent_channel")
        let decision = await router().route(message("command-2", source: .command, ts: "trigger-2"), client: client)
        guard case let .answer(turn)? = decision else { Issue.record("Command was not routed"); return }
        #expect(turn.session == .codeChannel(channel: "C1"))
        #expect(turn.replyThreadTs == nil)
    }

    @Test
    func `answers every person's message in a code channel in the channel's session`() async {
        await slack.channel(recordType: "agent_channel", origin: MessageLink(channel: "C0", ts: "0.5"))
        let router = router()
        let client = await slack.client()

        let topLevel = await router.route(message("E1", ts: "1.0", user: "U1"), client: client)
        #expect(topLevel == .answer(AgentResponder.Turn(
            session: .codeChannel(channel: "C1"),
            replyThreadTs: nil,
            messageTs: "1.0",
            prompt: "Hi",
            userId: "U1",
            teamId: "T1",
            origin: MessageLink(channel: "C0", ts: "0.5"),
        )))

        let threadReply = await router.route(message("E2", ts: "1.1", threadTs: "1.0", user: "U2"), client: client)
        guard case let .answer(turn)? = threadReply else {
            Issue.record("expected a turn, got \(String(describing: threadReply))")
            return
        }
        #expect(turn.session == .codeChannel(channel: "C1"))
        #expect(turn.replyThreadTs == "1.0")
        #expect(turn.userId == "U2")
        // The positive answer is cached.
        #expect(await slack.requests("conversationsInfo").count == 1)
    }

    @Test
    func `ignores top-level messages in other channels and answers their mentions in a thread`() async {
        await slack.channel(recordType: nil)
        let router = router()
        let client = await slack.client()

        #expect(await router.route(message("E1", ts: "1.0"), client: client) == nil)
        let mention = await router.route(message("E2", source: .mention, ts: "2.0"), client: client)
        guard case let .answer(turn)? = mention else {
            Issue.record("expected a turn, got \(String(describing: mention))")
            return
        }
        #expect(turn.session == .thread(channel: "C1", threadTs: "2.0"))
        #expect(turn.replyThreadTs == "2.0")
        // The negative answer is cached for a while.
        #expect(await slack.requests("conversationsInfo").count == 1)
    }

    @Test
    func `continues a thread in another channel only where the agent has replied`() async {
        await slack.channel(recordType: nil)
        await slack.reply(to: "conversationsReplies", with: .json("""
        {"ok":true,"messages":[{"type":"message","user":"U1","text":"Hi","ts":"1.0"}]}
        """), .json("""
        {"ok":true,"messages":[{"type":"message","user":"UBOT","text":"Hello","ts":"1.1"}]}
        """))
        await responder.setIdentity(BotIdentity(userId: "UBOT", botId: "B1"))
        let router = router()
        let client = await slack.client()

        #expect(await router.route(message("E1", ts: "1.2", threadTs: "1.0"), client: client) == nil)
        let reply = await router.route(message("E2", ts: "1.3", threadTs: "1.0"), client: client)
        guard case let .answer(turn)? = reply else {
            Issue.record("expected a turn, got \(String(describing: reply))")
            return
        }
        #expect(turn.session == .thread(channel: "C1", threadTs: "1.0"))
    }

    @Test
    func `answers a message once when it arrives as message and app_mention, and when Slack retries it`() async {
        await slack.channel(recordType: "agent_channel")
        let router = router()
        let client = await slack.client()

        #expect(await router.route(message("E1", source: .mention, ts: "1.0"), client: client) != nil)
        #expect(await router.route(message("E1", source: .mention, ts: "1.0"), client: client) == nil)
        #expect(await router.route(message("E2", ts: "1.0"), client: client) == nil)
        #expect(await router.route(message("E3", ts: "2.0"), client: client) != nil)
    }

    @Test
    func `leaves a message that mentions the bot to app_mention`() async {
        await slack.channel(recordType: "agent_channel")
        await responder.setIdentity(BotIdentity(userId: "UBOT", botId: "B1"))
        let router = router()
        let client = await slack.client()

        #expect(await router.route(message("E1", ts: "1.0", text: "<@UBOT> Hi"), client: client) == nil)
        #expect(await router.route(message("E2", source: .mention, ts: "1.0"), client: client) != nil)
    }

    @Test
    func `ignores the bot's own messages`() async {
        await slack.channel(recordType: "agent_channel")
        await responder.setIdentity(BotIdentity(userId: "UBOT", botId: "B1"))
        let router = router()
        let client = await slack.client()

        #expect(await router.route(message("E1", ts: "1.0", user: "UBOT"), client: client) == nil)
        #expect(await router.route(message("E2", isDirectMessage: true, ts: "2.0", user: "UBOT"), client: client) == nil)
    }

    @Test
    func `looks the channel up again after a failed lookup`() async {
        await slack.reply(
            to: "conversationsInfo",
            with: .transportFailure,
            .json(#"{"ok":false,"error":"ratelimited"}"#),
            .json(#"{"ok":true,"channel":{"id":"C1","properties":{"record_channel":{"record_type":"agent_channel"}}}}"#),
        )
        let router = router()
        let client = await slack.client()

        // Until Slack answers, the channel is treated as any channel, which ignores top-level messages.
        #expect(await router.route(message("E1", ts: "1.0"), client: client) == nil)
        #expect(await router.route(message("E2", ts: "2.0"), client: client) == nil)
        #expect(await router.route(message("E3", ts: "3.0"), client: client) != nil)
        #expect(await router.route(message("E4", ts: "4.0"), client: client) != nil)
        #expect(await slack.requests("conversationsInfo").count == 3)
    }

    @Test
    func `looks up a channel once for concurrent messages`() async {
        await slack.channel(recordType: "agent_channel")
        let router = router()
        let client = await slack.client()

        async let first = router.route(message("E1", ts: "1.0"), client: client)
        async let second = router.route(message("E2", ts: "2.0"), client: client)
        let decisions = await [first, second]
        #expect(decisions.allSatisfy { $0 != nil })
        #expect(await slack.requests("conversationsInfo").count == 1)
    }

    @Test
    func `keeps ALLOWED_USER_IDS in code channels, mentions, and direct messages`() async {
        await slack.channel(recordType: "agent_channel")
        let router = router(allowed: ["U1"])
        let client = await slack.client()

        let channel = await router.route(message("E1", ts: "1.0", user: "U2"), client: client)
        guard case let .notAllowed(turn)? = channel else {
            Issue.record("expected a notice, got \(String(describing: channel))")
            return
        }
        #expect(turn.replyThreadTs == nil)

        let direct = await router.route(message("E2", channel: "D1", isDirectMessage: true, ts: "2.0", user: "U2"), client: client)
        guard case let .notAllowed(directTurn)? = direct else {
            Issue.record("expected a notice, got \(String(describing: direct))")
            return
        }
        #expect(directTurn.session == .thread(channel: "D1", threadTs: "2.0"))
        #expect(await router.route(message("E3", ts: "3.0", user: "U1"), client: client) != nil)
    }

    @Test
    func `ignores thread replies from people not allowed in other channels`() async {
        await slack.channel(recordType: nil)
        let router = router(allowed: ["U1"])
        let client = await slack.client()
        #expect(await router.route(message("E1", ts: "1.1", threadTs: "1.0", user: "U2"), client: client) == nil)
        #expect(await slack.requests("conversationsReplies").isEmpty)
    }

    @Test
    func `a card's question goes into the reply's thread, or top-level in a code channel`() async {
        await slack.channel(recordType: "agent_channel")
        let router = router()
        let client = await slack.client()
        let topLevel = await router.destination(channel: "C1", threadTs: nil, messageTs: "1.0", client: client)
        #expect(topLevel.session == .codeChannel(channel: "C1"))
        #expect(topLevel.replyThreadTs == nil)

        let other = TurnRouterTests()
        await other.slack.channel(recordType: nil)
        let thread = await other.router().destination(
            channel: "C2",
            threadTs: nil,
            messageTs: "2.0",
            client: other.slack.client(),
        )
        #expect(thread.session == .thread(channel: "C2", threadTs: "2.0"))
        #expect(thread.replyThreadTs == "2.0")
    }

    func router(allowed: Set<String> = []) -> TurnRouter {
        TurnRouter(
            responder: responder,
            channels: ChannelClassifier(logger: Logger(label: "test")),
            isAllowed: { allowed.isEmpty || allowed.contains($0) },
            logger: Logger(label: "test"),
        )
    }

    func message(
        _ eventId: String,
        source: IncomingMessage.Source = .message,
        channel: String = "C1",
        isDirectMessage: Bool = false,
        ts: String,
        threadTs: String? = nil,
        user: String = "U1",
        text: String = "Hi",
    ) -> IncomingMessage {
        IncomingMessage(
            source: source,
            eventId: eventId,
            channel: channel,
            isDirectMessage: isDirectMessage,
            ts: ts,
            threadTs: threadTs,
            userId: user,
            text: text,
            teamId: "T1",
        )
    }
}

/// Stops that arrive while a message is still being routed, before its turn exists.
struct RoutingStopTests {
    let routing = TurnRouterTests()

    @Test(.timeLimit(.minutes(1)))
    func `channel stop discards a queued promotion before its turn registers`() async {
        let responder = routing.responder
        let router = routing.router()
        let attempt = responder.routingAttempts.begin(channel: "NEW", threadTs: nil, ts: "1.0")
        defer { responder.routingAttempts.end(attempt) }
        await router.stop(channel: "NEW", threadTs: nil)
        await responder.handle(.init(
            session: .codeChannel(channel: "NEW"), replyThreadTs: nil, messageTs: "1.0", prompt: "fix",
            userId: "U1", teamId: "T1",
        ), client: routing.slack.client(), attempt: attempt, parent: TurnProducer())
        #expect(await routing.slack.requests.isEmpty)
        #expect(await routing.backend.probe.prompts.isEmpty)
    }

    var slack: FakeSlack {
        routing.slack
    }

    var probe: BackendProbe {
        routing.backend.probe
    }

    @Test(.timeLimit(.minutes(1)))
    func `a channel stop discards a message waiting for its channel lookup, and a later message starts`() async {
        await slack.channel(recordType: "agent_channel")
        await slack.hold("conversationsInfo")
        let router = routing.router()
        let client = await slack.client()

        let routed = router.start(routing.message("E1", ts: "1.0"), client: client)
        await slack.waitFor("conversationsInfo")
        await router.stop(channel: "C1", threadTs: nil)
        await slack.release("conversationsInfo")
        await routed.value

        #expect(await slack.requests.map(\.method) == ["conversationsInfo"])
        #expect(await probe.prompts.isEmpty)
        #expect(router.attempts.isEmpty)

        let session = SessionKey.codeChannel(channel: "C1")
        let fresh = router.start(routing.message("E2", ts: "2.0"), client: client)
        await probe.waitForStart(of: session)
        await probe.release(session)
        await fresh.value
        #expect(await slack.requests("chatStartStream").count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a thread stop discards only the messages for that thread`() async {
        await slack.channel(recordType: nil)
        await slack.hold("conversationsInfo")
        let router = routing.router()
        let client = await slack.client()

        let other = router.start(routing.message("E1", source: .mention, ts: "1.0"), client: client)
        let stopped = router.start(routing.message("E2", source: .mention, ts: "2.1", threadTs: "2.0"), client: client)
        await slack.waitFor("conversationsInfo")
        await router.stop(channel: "C1", threadTs: "2.0")
        await slack.release("conversationsInfo")

        let session = SessionKey.thread(channel: "C1", threadTs: "1.0")
        await probe.waitForStart(of: session)
        await probe.release(session)
        await other.value
        await stopped.value
        #expect(await probe.prompts.keys.map(\.self) == [session])
        #expect(await slack.requests("chatStartStream").map { $0["thread_ts"] } == ["1.0"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stop discards a card's question before it is posted`() async {
        await slack.channel(recordType: "agent_channel")
        await slack.hold("conversationsInfo")
        let router = routing.router()
        let client = await slack.client()

        let asked = router.ask(.init(
            question: "Why?",
            channel: "C1",
            threadTs: nil,
            messageTs: "1.0",
            userId: "U1",
            teamId: "T1",
        ), client: client)
        await slack.waitFor("conversationsInfo")
        await router.stop(channel: "C1", threadTs: nil)
        await slack.release("conversationsInfo")
        await asked.value

        #expect(await slack.requests.map(\.method) == ["conversationsInfo"])
        #expect(await probe.prompts.isEmpty)
    }

    @Test
    func `a turn whose routing was stopped does not start`() async {
        let client = await slack.client()
        let attempts = RoutingAttempts()
        let attempt = attempts.begin(channel: "C1", threadTs: nil, ts: "1.0")
        let later = attempts.begin(channel: "C1", threadTs: nil, ts: "2.0")
        attempts.cancel(channel: "C1", threadTs: nil)
        let fresh = attempts.begin(channel: "C1", threadTs: nil, ts: "3.0")
        #expect(attempt.isCancelled && later.isCancelled)
        #expect(!fresh.isCancelled)

        await routing.responder.handle(AgentResponder.Turn(
            session: .codeChannel(channel: "C1"),
            replyThreadTs: nil,
            messageTs: "1.0",
            prompt: "Hi",
            userId: "U1",
            teamId: "T1",
        ), client: client, attempt: attempt)
        #expect(await slack.requests.isEmpty)
        #expect(await probe.prompts.isEmpty)
    }
}

struct RecentKeysTests {
    @Test
    func `forgets the oldest key beyond its capacity`() {
        var keys = RecentKeys(capacity: 2)
        let inserted = ["a", "a", "b", "c", "a", "c"].map { keys.insert($0) }
        #expect(inserted == [true, false, true, true, true, false])
    }
}

struct SlackAgentToolsTests {
    let slack = FakeSlack()

    @Test
    func `reads and renames a code channel's session`() async throws {
        let client = await slack.client()
        let topLevel = tools(client, replyThreadTs: nil)
        _ = try await topLevel.readSlack(.thread, limit: 5)
        #expect(await slack.requests.last?.method == "conversationsHistory")

        let inThread = tools(client, replyThreadTs: "1.0")
        _ = try await inThread.readSlack(.thread, limit: 5)
        #expect(await slack.requests.last?.method == "conversationsReplies")
        #expect(await slack.requests.last?["ts"] == "1.0")
        _ = try await inThread.readSlack(.channel, limit: 5)
        #expect(await slack.requests.last?.method == "conversationsHistory")

        try await inThread.setTitle("Build fix")
        let rename = await slack.requests("agentsSessionsRename").first
        #expect(rename?["channel_id"] == "C1")
        #expect(rename?["thread_ts"] == nil)
    }

    @Test
    func `does nothing in Slack once the session is stopped`() async {
        let client = await slack.client()
        let producer = TurnProducer()
        producer.stopSession()
        let tools = tools(client, replyThreadTs: "1.0", producer: producer)
        await #expect(throws: AgentToolError.self) { try await tools.setTitle("Title") }
        await #expect(throws: AgentToolError.self) { try await tools.askUser("Which?", options: ["A", "B"]) }
        #expect(await slack.requests.isEmpty)
    }

    private func tools(
        _ client: any APIProtocol,
        replyThreadTs: String?,
        producer: TurnProducer = TurnProducer(),
    ) -> SlackAgentTools {
        SlackAgentTools(
            client: client,
            session: .codeChannel(channel: "C1"),
            replyThreadTs: replyThreadTs,
            userId: "U1",
            identity: nil,
            questions: PendingQuestions(),
            isTitledByUser: { false },
            producer: producer,
        )
    }
}
