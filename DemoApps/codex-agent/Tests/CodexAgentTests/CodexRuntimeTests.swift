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
            let probe = RuntimeLifecycleProbe(heldRun: "drain")
            let slack = FakeSlack()
            let key = SessionKey.codeChannel(channel: "C1")
            let runtime = try CodexRuntime(
                settings: .init(workspace: source.path, sessionWorkspaces: root.path, idleTimeout: .zero),
                logger: .init(label: "test"),
                runSession: { session, prompt, _, _, _ in await probe.run(session, prompt: prompt) },
                closeSession: { _ in await probe.close() },
            )
            let firstTools = await lifecycleTools(slack, key: key)
            let first = await runtime.respond(to: "drain", in: key, tools: firstTools)
            await probe.waitForRun("drain")
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
            #expect(await probe.closes == 0)
            await probe.releaseRun()
            try await finish(first)
            await probe.waitForClose()
            #expect(await probe.closes == 1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a new turn waits for close and resumes its saved thread ID`() async throws {
        let probe = RuntimeLifecycleProbe(holdClose: true)
        let slack = FakeSlack()
        let key = SessionKey.thread(channel: "C1", threadTs: "1.0")
        let runtime = try CodexRuntime(
            settings: .init(workspace: "/tmp", idleTimeout: .zero), logger: .init(label: "test"),
            runSession: { session, prompt, _, _, _ in await probe.run(session, prompt: prompt) },
            closeSession: { _ in await probe.close() },
        )
        let tools = await lifecycleTools(slack, key: key)
        try await finish(runtime.respond(to: "first", in: key, tools: tools))
        await probe.waitForClose()
        let nextTools = await lifecycleTools(slack, key: key)
        let next = await runtime.respond(to: "second", in: key, tools: nextTools)
        #expect(await probe.runs["second"] == nil)
        await probe.releaseClose()
        try await finish(next)
        #expect(await probe.threadIDs["second"] == "saved-conversation")
    }

    @Test(.timeLimit(.minutes(1)))
    func `failed workspace validation restores idle cleanup for the existing session`() async throws {
        try await SessionWorkspacesTests().withRepository { source, root in
            let probe = RuntimeLifecycleProbe()
            let slack = FakeSlack()
            let key = SessionKey.codeChannel(channel: "C1")
            let runtime = try CodexRuntime(
                settings: .init(workspace: source.path, sessionWorkspaces: root.path), logger: .init(label: "test"),
                runSession: { session, prompt, _, _, _ in await probe.run(session, prompt: prompt) },
                closeSession: { _ in await probe.close() },
            )
            let firstTools = await lifecycleTools(slack, key: key)
            try await finish(runtime.respond(to: "first", in: key, tools: firstTools))
            let oldTimer = try #require(await runtime.idleTimers[key])
            try Data("blocked".utf8).write(to: root.appending(path: "code-C1/.env"))
            let nextTools = await lifecycleTools(slack, key: key)
            let next = await runtime.respond(to: "invalid", in: key, tools: nextTools)
            await #expect(throws: AgentToolError.self) { try await finish(next) }
            let timer = try #require(await runtime.idleTimers[key])
            defer { timer.cancel() }
            #expect(oldTimer.isCancelled)
            #expect(!timer.isCancelled)
            #expect(await runtime.activeRuns[key] == nil)
            #expect(await probe.runs["invalid"] == nil)
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

private actor RuntimeLifecycleProbe {
    private let heldRun: String?
    private var holdClose: Bool
    private var runRelease: CheckedContinuation<Void, Never>?
    private var closeRelease: CheckedContinuation<Void, Never>?
    private var runWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var runs: [String: Int] = [:]
    private(set) var threadIDs: [String: String] = [:]
    private(set) var closes = 0

    init(heldRun: String? = nil, holdClose: Bool = false) {
        self.heldRun = heldRun
        self.holdClose = holdClose
    }

    func run(_ session: CodexSession, prompt: String) async {
        threadIDs[prompt] = await session.threadID
        runs[prompt, default: 0] += 1
        for waiter in runWaiters.removeValue(forKey: prompt) ?? [] {
            waiter.resume()
        }
        if prompt == heldRun {
            await withCheckedContinuation { runRelease = $0 }
        }
    }

    func close() async -> String? {
        closes += 1
        for waiter in closeWaiters {
            waiter.resume()
        }
        closeWaiters.removeAll()
        if holdClose {
            await withCheckedContinuation { closeRelease = $0 }
        }
        return "saved-conversation"
    }

    func waitForRun(_ prompt: String) async {
        guard runs[prompt] == nil else { return }
        await withCheckedContinuation { runWaiters[prompt, default: []].append($0) }
    }

    func waitForClose() async {
        guard closes == 0 else { return }
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    func releaseRun() {
        runRelease?.resume()
        runRelease = nil
    }

    func releaseClose() {
        holdClose = false
        closeRelease?.resume()
        closeRelease = nil
    }
}
