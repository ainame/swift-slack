@testable import CodexAgent
import Testing

struct CodexRuntimeTests {
    @Test(arguments: [TurnProducer.Reason.cancelled, .sessionStopped])
    func `a producer stopped before runtime registration never launches Codex`(reason: TurnProducer.Reason) async throws {
        let producer = TurnProducer()
        switch reason {
        case .cancelled: producer.cancel()
        case .sessionStopped: producer.stopSession()
        }
        let slack = FakeSlack()
        let session = SessionKey.codeChannel(channel: "C1")
        let runtime = try CodexRuntime(
            settings: .init(codexPath: "/nonexistent/codex-agent-test", workspace: "/tmp"),
            logger: .init(label: "test"),
        )
        let tools = await SlackAgentTools(
            client: slack.client(), session: session, replyThreadTs: nil, userId: "U1", identity: nil,
            questions: .init(), isTitledByUser: { false }, producer: producer,
        )
        let stream = await runtime.respond(to: "Must not run", in: session, tools: tools)
        var events = 0
        // Launching the deliberately unavailable executable would throw rather than finish quietly.
        for try await _ in stream {
            events += 1
        }
        #expect(events == 0)
        await runtime.stop(in: session, producer: producer)
    }

    @Test(arguments: [true, false])
    func `runtime interruption targets only its registered turn`(sameTurn: Bool) async throws {
        let producer = TurnProducer()
        let slack = FakeSlack()
        let session = SessionKey.thread(channel: "C1", threadTs: "1.0")
        let runtime = try CodexRuntime(
            settings: .init(codexPath: "/nonexistent/codex-agent-test", workspace: "/tmp"),
            logger: .init(label: "test"),
        )
        let tools = await SlackAgentTools(
            client: slack.client(), session: session, replyThreadTs: "1.0", userId: "U1", identity: nil,
            questions: .init(), isTitledByUser: { false }, producer: producer,
        )
        let stream = await registerAndStop(
            runtime, session: session, tools: tools, stoppedProducer: sameTurn ? producer : TurnProducer(),
        )
        if sameTurn {
            var events = 0
            for try await _ in stream {
                events += 1
            }
            #expect(events == 0)
        } else {
            // An old turn's stop must not cancel the new turn: it attempts the unavailable executable.
            await #expect(throws: (any Error).self) {
                for try await _ in stream {}
            }
        }
    }

    // Keep registration and stop in one actor operation so the scheduled turn cannot run between them.
    private func registerAndStop(
        _ runtime: isolated CodexRuntime,
        session: SessionKey,
        tools: SlackAgentTools,
        stoppedProducer: TurnProducer,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        let stream = runtime.respond(to: "Test", in: session, tools: tools)
        runtime.stop(in: session, producer: stoppedProducer)
        return stream
    }
}
