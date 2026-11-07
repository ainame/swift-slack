@testable import CodexAgent
import Foundation
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

    @Test(.timeLimit(.minutes(1)))
    func `a stopped newer run cannot idle close an older draining run`() async throws {
        try await SessionWorkspacesTests().withRepository { source, root in
            let server = try FakeCodexAppServer()
            defer { server.cleanup() }
            let slack = FakeSlack()
            let key = SessionKey.codeChannel(channel: "C1")
            let runtime = try CodexRuntime(
                settings: .init(codexPath: server.executable.path, workspace: source.path, sessionWorkspaces: root.path, idleTimeout: .zero),
                logger: .init(label: "test"),
            )
            let firstTools = await lifecycleTools(slack, key: key)
            let first = await runtime.respond(to: "drain", in: key, tools: firstTools)
            try await server.waitFor("turn/start")
            firstTools.producer.stopSession()
            await runtime.stop(in: key, producer: firstTools.producer)
            try await server.waitFor("turn/interrupt")
            await slack.hold("agentsConversationsSetProperties")
            let secondTools = await lifecycleTools(slack, key: key)
            let second = await runtime.respond(to: "queued", in: key, tools: secondTools)
            await slack.wait { $0.filter { $0.method == "agentsConversationsSetProperties" }.count == 2 }
            secondTools.producer.stopSession()
            await runtime.stop(in: key, producer: secondTools.producer)
            await slack.release("agentsConversationsSetProperties")
            try await finish(second)
            #expect(await runtime.activeRuns[key] == 1)
            #expect(await runtime.idleTimers[key] == nil)
            #expect(server.exitedProcessCount == 0)
            #expect(server.requests("turn/start").count == 1)
            try server.releaseDrain()
            try await finish(first)
            try await server.waitForExit()
            #expect(server.exitedProcessCount == 1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `idle close launches a fresh app server and resumes its saved thread ID`() async throws {
        let server = try FakeCodexAppServer()
        defer { server.cleanup() }
        let slack = FakeSlack()
        let key = SessionKey.thread(channel: "C1", threadTs: "1.0")
        let runtime = try CodexRuntime(
            settings: .init(codexPath: server.executable.path, workspace: "/tmp", idleTimeout: .zero), logger: .init(label: "test"),
        )
        let tools = await lifecycleTools(slack, key: key)
        try await finish(runtime.respond(to: "first", in: key, tools: tools))
        try await server.waitForExit()
        let nextTools = await lifecycleTools(slack, key: key)
        let next = await runtime.respond(to: "second", in: key, tools: nextTools)
        try await finish(next)
        try await server.waitForExit(count: 2)
        #expect(server.requests("launched").count == 2)
        #expect(server.requests("thread/start").count == 1)
        let resume = try #require(server.requests("thread/resume").first?["params"] as? [String: Any])
        #expect(resume["threadId"] as? String == "saved-conversation")
    }

    @Test(.timeLimit(.minutes(1)))
    func `failed workspace validation restores idle cleanup for the existing session`() async throws {
        try await SessionWorkspacesTests().withRepository { source, root in
            let server = try FakeCodexAppServer()
            defer { server.cleanup() }
            let slack = FakeSlack()
            let key = SessionKey.codeChannel(channel: "C1")
            let runtime = try CodexRuntime(
                settings: .init(codexPath: server.executable.path, workspace: source.path, sessionWorkspaces: root.path, idleTimeout: .seconds(1)), logger: .init(label: "test"),
            )
            let firstTools = await lifecycleTools(slack, key: key)
            try await finish(runtime.respond(to: "first", in: key, tools: firstTools))
            let oldTimer = try #require(await runtime.idleTimers[key])
            try Data("blocked".utf8).write(to: root.appending(path: "code-C1/.env"))
            let nextTools = await lifecycleTools(slack, key: key)
            let next = await runtime.respond(to: "invalid", in: key, tools: nextTools)
            await #expect(throws: AgentToolError.self) { try await finish(next) }
            let timer = try #require(await runtime.idleTimers[key])
            #expect(oldTimer.isCancelled)
            #expect(!timer.isCancelled)
            #expect(await runtime.activeRuns[key] == nil)
            #expect(server.requests("turn/start").count == 1)
            try await server.waitForExit()
        }
    }

    private func lifecycleTools(_ slack: FakeSlack, key: SessionKey) async -> SlackAgentTools {
        await SlackAgentTools(
            client: slack.client(), session: key, replyThreadTs: key.threadTs, userId: "U1", identity: nil,
            questions: .init(), isTitledByUser: { false }, producer: .init(),
        )
    }

    private func finish(_ stream: AsyncThrowingStream<AgentEvent, any Error>) async throws {
        for try await _ in stream {}
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
