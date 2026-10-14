@testable import CodexAgent
import Logging
import SlackKit
import Testing

struct AgentResponderTests {
    let slack = FakeSlack()
    let codex: ScriptedCodex
    let questions = PendingQuestions()
    let responder: AgentResponder

    init() {
        self.init(asksQuestion: false)
    }

    private init(asksQuestion: Bool) {
        codex = ScriptedCodex(asksQuestion: asksQuestion)
        responder = AgentResponder(events: { [codex] in codex.respond(to: $0, in: $1, tools: $2) }, interrupt: { _ in }, questions: questions, logger: Logger(label: "test"))
    }

    @Test(.timeLimit(.minutes(1)))
    func `replies top-level for a code channel message and in the thread for a thread session`() async {
        let client = await slack.client()
        let channelTurn = turn(.codeChannel(channel: "C1"), replyThreadTs: nil)
        let threadTurn = turn(.thread(channel: "C2", threadTs: "2.0"), replyThreadTs: "2.0", messageTs: "2.0")

        async let channelReply: Void = responder.handle(channelTurn, client: client)
        async let threadReply: Void = responder.handle(threadTurn, client: client)
        await codex.probe.waitForStart(of: channelTurn.session)
        await codex.probe.waitForStart(of: threadTurn.session)
        await codex.probe.release(channelTurn.session)
        await codex.probe.release(threadTurn.session)
        _ = await (channelReply, threadReply)

        let starts = await slack.requests("chatStartStream")
        #expect(starts.first { $0["channel"] == "C1" }?["thread_ts"] == nil)
        #expect(starts.first { $0["channel"] == "C2" }?["thread_ts"] == "2.0")
        let processing = await slack.requests("agentsSessionsSetStatus").filter { $0["status"] == "processing" }
        #expect(processing.first { $0["channel_id"] == "C1" }?["thread_ts"] == nil)
        #expect(processing.first { $0["channel_id"] == "C2" }?["thread_ts"] == "2.0")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a code channel is busy for everyone while sessions elsewhere run at the same time`() async {
        let client = await slack.client()
        let first = turn(.codeChannel(channel: "C1"), replyThreadTs: nil)
        let elsewhere = turn(.thread(channel: "C2", threadTs: "2.0"), replyThreadTs: "2.0", messageTs: "2.0")

        async let firstReply: Void = responder.handle(first, client: client)
        await codex.probe.waitForStart(of: first.session)
        async let elsewhereReply: Void = responder.handle(elsewhere, client: client)
        await codex.probe.waitForStart(of: elsewhere.session)

        // Another person replies in a thread of the code channel while its session is busy.
        await responder.handle(
            turn(.codeChannel(channel: "C1"), replyThreadTs: "1.5", messageTs: "1.6", userId: "U2"),
            client: client,
        )
        let notices = await slack.requests("chatPostEphemeral")
        #expect(notices.count == 1)
        #expect(notices.first?["channel"] == "C1")
        #expect(notices.first?["thread_ts"] == "1.5")
        #expect(notices.first?["user"] == "U2")
        #expect(notices.first?["text"]?.contains("earlier message in this channel") == true)
        #expect(await codex.probe.prompts[first.session]?.count == 1)

        await codex.probe.release(first.session)
        await codex.probe.release(elsewhere.session)
        _ = await (firstReply, elsewhereReply)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stop cancels the turn and clears processing without sending more stream content`() async {
        let client = await slack.client()
        let stopped = turn(.codeChannel(channel: "C1"), replyThreadTs: nil)

        let handling = Task { await responder.handle(stopped, client: client) }
        await codex.probe.waitForStart(of: stopped.session)
        await slack.waitFor("chatStartStream")
        await slack.waitFor("agentsSessionsSetStatus")
        let before = await slack.requests.count

        await responder.stop(channel: "C1", threadTs: nil)
        await handling.value

        await codex.probe.waitFor("cancelled", in: stopped.session)
        let after = await slack.requests.dropFirst(before)
        #expect(after.map(\.method) == ["agentsSessionsSetStatus"])
        #expect(after.first?["status"] == "active")
        #expect(await slack.requests.allSatisfy { $0["chunks"]?.contains("Stopped") != true })

        // The session is free again.
        let next = Task { await responder.handle(stopped, client: client) }
        await codex.probe.waitForStart(of: stopped.session, count: 2)
        await codex.probe.release(stopped.session)
        await next.value
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stop before streaming starts is kept and nothing reaches Slack`() async {
        let client = await slack.client()
        // conversations.history never answers, which holds the turn in its setup until the stop.
        await slack.hold("conversationsHistory")
        let stopped = turn(.codeChannel(channel: "C1"), replyThreadTs: nil, messageTs: "9.0")
        let handling = Task { await responder.handle(stopped, client: client) }
        await slack.waitFor("conversationsHistory")
        await responder.stop(channel: "C1", threadTs: nil)
        await handling.value

        #expect(await slack.requests("chatStartStream").isEmpty)
        #expect(await slack.requests("chatStopStream").isEmpty)
        #expect(await slack.requests("agentsSessionsSetStatus").last?["status"] == "active")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stop ends a waiting question and clears session status without updating the question`() async {
        let test = AgentResponderTests(asksQuestion: true)
        let client = await test.slack.client()
        let session = SessionKey.codeChannel(channel: "C1")
        let asking = test.turn(session, replyThreadTs: "1.5", messageTs: "1.6")

        let handling = Task { await test.responder.handle(asking, client: client) }
        await test.slack.waitFor("agentsSessionsSetStatus") { $0["status"] == "suspended" }
        // Parts yielded before the stop may still go out, so wait for the one the turn yielded first.
        await test.slack.waitFor("chatStartStream")
        let question = await test.slack.requests("chatPostMessage").first
        #expect(question?["channel"] == "C1")
        #expect(question?["thread_ts"] == "1.5")
        let before = await test.slack.requests.count

        await test.responder.stop(channel: "C1", threadTs: "1.5")
        await test.codex.probe.waitFor("question ended", in: session)
        await handling.value

        let after = await test.slack.requests.dropFirst(before)
        #expect(after.map(\.method) == ["agentsSessionsSetStatus"])
        #expect(after.first?["status"] == "active")
        #expect(await test.slack.requests("agentsSessionsSetStatus").allSatisfy { $0["thread_ts"] == nil })
    }

    @Test(.timeLimit(.minutes(1)))
    func `a thread stop matches its session and a channel stop ends every turn in the channel`() async {
        let client = await slack.client()
        let first = turn(.thread(channel: "C1", threadTs: "1.0"), replyThreadTs: "1.0", messageTs: "1.0")
        let second = turn(.thread(channel: "C1", threadTs: "2.0"), replyThreadTs: "2.0", messageTs: "2.0")
        let elsewhere = turn(.thread(channel: "C2", threadTs: "3.0"), replyThreadTs: "3.0", messageTs: "3.0")
        let handlings = [first, second, elsewhere].map { turn in
            Task { await responder.handle(turn, client: client) }
        }
        for turn in [first, second, elsewhere] {
            await codex.probe.waitForStart(of: turn.session)
        }

        await responder.stop(channel: "C1", threadTs: "2.0")
        await handlings[1].value
        // The other thread in the channel is still busy.
        await responder.handle(first, client: client)
        #expect(await slack.requests("chatPostEphemeral").map { $0["thread_ts"] } == ["1.0"])

        await responder.stop(channel: "C1", threadTs: nil)
        await handlings[0].value
        await responder.handle(elsewhere, client: client)
        #expect(await slack.requests("chatPostEphemeral").map { $0["thread_ts"] } == ["1.0", "3.0"])

        await codex.probe.release(elsewhere.session)
        await handlings[2].value
        #expect(await slack.requests("chatStopStream").map { $0["channel"] } == ["C2"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a delivery failure still sets the session back to active`() async {
        await slack.reply(to: "chatStartStream", with: .json(#"{"ok":false,"error":"channel_not_found"}"#))
        let client = await slack.client()
        let failing = turn(.codeChannel(channel: "C1"), replyThreadTs: nil)

        let handling = Task { await responder.handle(failing, client: client) }
        await slack.waitFor("chatStartStream")
        // Delivery failure cancels the paused input and joins production without another codex event.
        await handling.value

        let active = await slack.requests("agentsSessionsSetStatus").filter { $0["status"] == "active" }
        #expect(active.count == 1)
        #expect(active.first?["channel_id"] == "C1")
        #expect(active.first?["thread_ts"] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a code channel's first prompt starts with its history, oldest first, and its origin`() async {
        await slack.reply(to: "conversationsHistory", with: .json("""
        {"ok":true,"messages":[
          {"type":"message","user":"U2","text":"second","ts":"2.0"},
          {"type":"message","user":"U1","text":"first","ts":"1.0"}
        ]}
        """), .json("""
        {"ok":true,"messages":[{"type":"message","user":"U3","text":"Fix the build","ts":"0.5"}]}
        """))
        let client = await slack.client()
        var first = turn(.codeChannel(channel: "C1"), replyThreadTs: nil, messageTs: "3.0")
        first.origin = MessageLink(channel: "C0", ts: "0.5")

        let handling = Task { await responder.handle(first, client: client) }
        await codex.probe.waitForStart(of: first.session)
        await codex.probe.release(first.session)
        await handling.value

        let prompt = await codex.probe.prompts[first.session]?.first ?? ""
        #expect(prompt.contains("<@U3>: Fix the build"))
        let firstIndex = prompt.range(of: "<@U1>: first")?.lowerBound
        let secondIndex = prompt.range(of: "<@U2>: second")?.lowerBound
        #expect(firstIndex != nil && secondIndex != nil && firstIndex! < secondIndex!)
        #expect(prompt.hasSuffix("Hi"))
        let origin = await slack.requests("conversationsHistory").last
        #expect(origin?["channel"] == "C0")
        #expect(origin?["latest"] == "0.5")
    }

    @Test(.timeLimit(.minutes(1)))
    func `code channel context restores paginated thread replies in chronological order`() async {
        await slack.reply(to: "conversationsHistory", with: .json("""
        {"ok":true,"messages":[
          {"text":"latest top-level","ts":"3.0"},
          {"text":"thread parent","ts":"1.0","reply_count":2}
        ]}
        """))
        await slack.reply(to: "conversationsReplies", with: .json("""
        {"ok":true,"messages":[
          {"text":"thread parent","ts":"1.0"},
          {"text":"first decision","ts":"2.0","thread_ts":"1.0"}
        ],"response_metadata":{"next_cursor":"page-2"}}
        """), .json("""
        {"ok":true,"messages":[
          {"text":"final decision","ts":"4.0","thread_ts":"1.0"},
          {"text":"current input","ts":"5.0","thread_ts":"1.0"}
        ],"response_metadata":{"next_cursor":""}}
        """))
        let first = turn(.codeChannel(channel: "C1"), replyThreadTs: "1.0", messageTs: "5.0")
        let client = await slack.client()
        let handling = Task { await responder.handle(first, client: client) }
        await codex.probe.waitForStart(of: first.session)
        await codex.probe.release(first.session)
        await handling.value
        let prompt = await codex.probe.prompts[first.session]?.first ?? ""
        let expected = ["thread parent", "first decision", "latest top-level", "final decision"]
        let positions = expected.compactMap { prompt.range(of: $0)?.lowerBound }
        #expect(positions.count == expected.count)
        #expect(positions == positions.sorted())
        #expect(prompt.components(separatedBy: "thread parent").count == 2)
        #expect(!prompt.contains("current input"))
        let requests = await slack.requests("conversationsReplies")
        #expect(requests.count == 2)
        #expect(requests.last?["cursor"] == "page-2")
    }

    private func turn(
        _ session: SessionKey,
        replyThreadTs: String?,
        messageTs: String = "1.0",
        userId: String = "U1",
    ) -> AgentResponder.Turn {
        AgentResponder.Turn(
            session: session,
            replyThreadTs: replyThreadTs,
            messageTs: messageTs,
            prompt: "Hi",
            userId: userId,
            teamId: "T1",
        )
    }
}
