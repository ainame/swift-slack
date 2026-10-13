@testable import CodexAgent
import Logging
import SlackKit
import Synchronization
import Testing

struct StopControlTests {
    @Test(arguments: [true, false])
    func `Codex interruption is sent once whether stop arrives before or after turn registration`(stopFirst: Bool) async {
        let control = TurnControl()
        let calls = Mutex(0)
        if stopFirst {
            control.cancel()
        }
        control.attachInterruption { calls.withLock { $0 += 1 } }
        control.cancel()
        control.cancel()
        await control.waitForInterruption()
        #expect(control.isCancelled)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `stop directly interrupts blocked output and only native stops reactivate the session`(resetStatus: Bool) async {
        let slack = FakeSlack()
        await slack.hold("agentsConversationsSetView")
        let backend = BlockedOutputBackend()
        let responder = AgentResponder(backend: backend, questions: .init(), logger: .init(label: "test"))
        let client = await slack.client()
        let task = Task {
            await responder.handle(.init(
                session: .codeChannel(channel: "C1"),
                replyThreadTs: nil,
                messageTs: "1.0",
                prompt: "Edit",
                userId: "U1",
                teamId: "T1",
            ), client: client)
        }
        await slack.waitFor("agentsConversationsSetView")
        await responder.stop(channel: "C1", threadTs: nil, resetStatus: resetStatus)
        #expect(backend.stopped.withLock { $0 })
        await task.value
        #expect(await slack.requests("agentsSessionsSetStatus").last?["status"] == (resetStatus ? "active" : "processing"))
        #expect(await slack.requests("chatAppendStream").isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["unrelated-thread", ""])
    func `Code channel stop ignores thread timestamps and stops its shared top level turn`(threadTs: String) async {
        let setup = TurnRouterTests()
        await setup.slack.channel(recordType: "agent_channel")
        let router = setup.router()
        let client = await setup.slack.client()
        let task = router.start(setup.message("E1", ts: "1.0"), client: client)
        await setup.backend.probe.waitForStart(of: .codeChannel(channel: "C1"))
        await router.stop(channel: "C1", threadTs: threadTs, client: client)
        await task.value
        await setup.backend.probe.waitFor("cancelled", in: .codeChannel(channel: "C1"))
        let active = await setup.slack.requests("agentsSessionsSetStatus").last
        #expect(active?["status"] == "active")
        #expect(active?["thread_ts"] == nil)
    }

    @Test
    func `a stop with no running turn still clears stale Slack processing status`() async {
        let setup = TurnRouterTests()
        await setup.router().stop(channel: "C1", threadTs: nil, client: setup.slack.client())
        #expect(await setup.slack.requests("agentsSessionsSetStatus").last?["status"] == "active")
    }
}

private final class BlockedOutputBackend: AgentBackend {
    let stopped = Mutex(false)
    func stop(in _: SessionKey) {
        stopped.withLock { $0 = true }
    }

    func respond(to _: String, in _: SessionKey, tools _: any AgentTools) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.diff("diff --git a/file b/file"))
            // The consumer is held in publishView. Do not couple command cancellation to stream termination.
        }
    }
}
