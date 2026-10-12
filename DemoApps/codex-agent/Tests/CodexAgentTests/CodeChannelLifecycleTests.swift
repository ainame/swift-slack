import Codex
@testable import CodexAgent
import Foundation
import Logging
import SlackKit
import Testing

struct CodeChannelLifecycleTests {
    @Test
    func `promotion is idempotent and configures commands without slashes`() async throws {
        let slack = FakeSlack()
        await slack.reply(to: "agentsConversationsCreate", with: .json(#"{"ok":true,"channel_id":"CODE"}"#))
        let tools = await tools(slack, session: .thread(channel: "C1", threadTs: "1.0"))
        #expect(try await tools.startCodeChannel(name: "fix-bug") == "CODE")
        #expect(try await tools.startCodeChannel(name: "fix-bug") == "CODE")
        let requests = await slack.requests("agentsConversationsCreate")
        #expect(requests.count == 1)
        #expect(requests.first?["session_id"] == "swift-slack-codex:C1/1.0")
        #expect(requests.first?["origin_channel_id"] == "C1")
        #expect(requests.first?["origin_message_ts"] == "1.0")
        let commands = try #require(await slack.requests("agentsConversationsSetCommands").first?["commands"])
        let json = try JSONSerialization.jsonObject(with: Data(commands.utf8)) as? [[String: Any]]
        #expect(json?.compactMap { $0["name"] as? String } == ["review", "run"])
    }

    @Test
    func `existing code channels do not create another channel`() async throws {
        let slack = FakeSlack()
        let tools = await tools(slack)
        #expect(try await tools.startCodeChannel(name: "ignored") == "CODE")
        #expect(await slack.requests.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `stop during creation prevents setup and launch`() async {
        let slack = FakeSlack()
        await slack.hold("agentsConversationsCreate")
        await slack.reply(to: "agentsConversationsCreate", with: .json(#"{"ok":true,"channel_id":"CODE"}"#))
        let producer = TurnProducer()
        let tools = await tools(slack, session: .thread(channel: "C1", threadTs: "1.0"), producer: producer)
        let task = Task { try await tools.startCodeChannel(name: "fix") }
        await slack.waitFor("agentsConversationsCreate")
        producer.stopSession()
        await slack.release("agentsConversationsCreate")
        do { _ = try await task.value; Issue.record("A stopped turn created a channel") } catch {}
        #expect(await slack.requests.map(\.method) == ["agentsConversationsCreate"])
    }

    @Test
    func `archive attaches a top-level summary before ending the session`() async throws {
        let slack = FakeSlack()
        let producer = TurnProducer()
        var tools = await tools(slack, producer: producer)
        tools.endSession = { producer.stopSession() }
        try await tools.archiveCodeChannel(summary: "Fixed the bug; tests pass.")
        let requests = await slack.requests
        #expect(requests.map(\.method) == ["chatPostMessage", "agentsConversationsSetProperties", "agentsConversationsArchive"])
        #expect(requests.first?["thread_ts"] == nil)
        #expect(requests[1]["code_channel"]?.contains("summary_message") == true)
        #expect(requests[2]["summary_message_ts"] == nil)
        #expect(producer.isSessionStopped)
        do { try await tools.publishView(.diff(content: "x")); Issue.record("Published after archive") } catch {}
        #expect(await slack.requests.count == 3)
    }

    @Test(arguments: [true, false])
    func `archive shares a summary for channels with a known origin`(createdHere: Bool) async throws {
        let slack = FakeSlack()
        let lifecycle = CodeChannelLifecycle()
        if createdHere {
            await slack.reply(to: "agentsConversationsCreate", with: .json(#"{"ok":true,"channel_id":"CODE"}"#))
            _ = try await lifecycle.create(
                name: "fix", from: .thread(channel: "C0", threadTs: "1.0"), messageTs: "1.0",
                client: slack.client(), producer: .init(), logger: .init(label: "test"),
            )
        }
        var tools = await tools(slack)
        tools.lifecycle = lifecycle
        if !createdHere {
            tools.origin = .init(channel: "C0", ts: "1.0")
        }
        try await tools.archiveCodeChannel(summary: "Fixed.")
        let archive = try #require(await slack.requests("agentsConversationsArchive").first)
        #expect(archive["summary_message_ts"] == FakeSlack.ts)
    }

    @Test
    func `view tool parses HTML Canvas and Block Kit arguments`() throws {
        let decoder = JSONDecoder()
        let html = try decoder.decode(
            AgentToolset.CodeViewArguments.self,
            from: Data(#"{"type":"html","key":"report","content":"<html>ok</html>","resource_domains":["https://cdn.example.com"]}"#.utf8),
        )
        #expect(try html.view() == .html(key: "report", content: "<html>ok</html>", csp: .init(resourceDomains: ["https://cdn.example.com"])))
        let canvas = try decoder.decode(AgentToolset.CodeViewArguments.self, from: Data(#"{"type":"canvas","key":"notes","canvas_id":"F1"}"#.utf8))
        #expect(try canvas.view() == .canvas(key: "notes", canvasId: "F1", accessLevel: .comment))
        let blocks = try decoder.decode(AgentToolset.CodeViewArguments.self, from: Data(#"{"type":"block_kit","key":"report","content":"[{\"type\":\"divider\"}]"}"#.utf8))
        guard case let .blockKit(key, blocks, _) = try blocks.view() else { Issue.record("Wrong view"); return }
        #expect(key == "report")
        #expect(blocks.count == 1)
    }

    @Test
    func `Codex diff notifications become code channel view updates`() async {
        let slack = FakeSlack()
        let responder = AgentResponder(backend: DiffBackend(), questions: PendingQuestions(), logger: .init(label: "test"))
        let client = await slack.client()
        await responder.handle(.init(
            session: .codeChannel(channel: "CODE"),
            replyThreadTs: nil,
            messageTs: "1.0",
            prompt: "fix",
            userId: "U1",
            teamId: "T1",
        ), client: client)
        let views = await slack.requests("agentsConversationsSetView")
        #expect(views.count == 1)
        #expect(views.first?["type"] == "diff")
        #expect(views.first?["content"] == "+fixed")
        await responder.handle(.init(
            session: .thread(channel: "C1", threadTs: "2.0"),
            replyThreadTs: "2.0",
            messageTs: "2.0",
            prompt: "review",
            userId: "U1",
            teamId: "T1",
        ), client: client)
        #expect(await slack.requests("agentsConversationsSetView").count == 1)
    }

    @Test(arguments: ["agentsConversationsSetProperties", "agentsConversationsSetCommands"])
    func `decoration failures still launch the original task once`(method: String) async throws {
        let slack = FakeSlack()
        await slack.reply(to: "agentsConversationsCreate", with: .json(#"{"ok":true,"channel_id":"CODE"}"#))
        await slack.reply(to: method, with: .json(#"{"ok":false,"error":"missing_scope"}"#))
        var tools = await tools(slack, session: .thread(channel: "C1", threadTs: "1.0"))
        let launches = Launches()
        tools.onCodeChannel = { channel in await launches.record(channel) }
        #expect(try await tools.startCodeChannel(name: "fix") == "CODE")
        #expect(try await tools.startCodeChannel(name: "fix") == "CODE")
        #expect(await launches.channels == ["CODE"])
        #expect(await slack.requests("agentsConversationsCreate").count == 1)
        // Even if a later lookup incorrectly routes a created Code channel as a thread, never nest it.
        let nested = try await tools.lifecycle.create(
            name: "nested", from: .thread(channel: "CODE", threadTs: "2.0"), messageTs: "2.0",
            client: slack.client(), producer: .init(), logger: .init(label: "test"),
        )
        #expect(nested.channel == "CODE")
        #expect(!nested.shouldLaunch)
        #expect(await slack.requests("agentsConversationsCreate").count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `promoted tasks continue after a rename failure without another handoff`() async {
        let slack = FakeSlack()
        await slack.reply(to: "agentsConversationsCreate", with: .json(#"{"ok":true,"channel_id":"CODE"}"#))
        await slack.reply(to: "agentsSessionsRename", with: .json(#"{"ok":false,"error":"invalid_name"}"#))
        let backend = PromotionBackend()
        let responder = AgentResponder(backend: backend, questions: PendingQuestions(), logger: .init(label: "test"))
        let origin = SessionKey.thread(channel: "C1", threadTs: "1.0")
        let client = await slack.client()
        await responder.handle(.init(
            session: origin, replyThreadTs: "1.0", messageTs: "1.0",
            prompt: "Fix the bug", userId: "U1", teamId: "T1",
        ), client: client)
        await backend.probe.waitFor("continued", in: .codeChannel(channel: "CODE"))
        await slack.waitFor("chatStopStream", where: { $0["channel"] == "CODE" })
        #expect(await slack.requests("agentsConversationsCreate").count == 1)
        #expect(await backend.probe.prompts[.codeChannel(channel: "CODE")]?.count == 1)
        #expect(await backend.probe.events[.codeChannel(channel: "CODE")]?.contains("rename failed") == true)
        let chunks = await slack.requests.filter { $0["channel"] == "CODE" }.compactMap { $0["chunks"] }.joined()
        #expect(chunks.contains("Working here"))
    }

    private func tools(
        _ slack: FakeSlack,
        session: SessionKey = .codeChannel(channel: "CODE"),
        producer: TurnProducer = .init(),
    ) async -> SlackAgentTools {
        await SlackAgentTools(
            client: slack.client(),
            session: session,
            replyThreadTs: nil,
            userId: "U1",
            identity: nil,
            questions: PendingQuestions(),
            isTitledByUser: { false },
            producer: producer,
            messageTs: "1.0",
        )
    }
}

private struct DiffBackend: AgentBackend {
    func respond(to _: String, in _: SessionKey, tools _: any AgentTools) -> AsyncThrowingStream<AgentEvent, any Error> {
        var translator = NotificationTranslator(turnID: "turn")
        let events = translator.events(turnID: "turn", payload: .turnDiffUpdated(.init(diff: "+fixed", threadId: "thread", turnId: "turn")))
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.yield(.text("Done"))
            continuation.finish()
        }
    }
}

private actor Launches {
    private(set) var channels: [String] = []
    func record(_ channel: String) {
        channels.append(channel)
    }
}

private struct PromotionBackend: AgentBackend {
    let probe = BackendProbe()

    func respond(to prompt: String, in session: SessionKey, tools: any AgentTools) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                _ = await probe.start(session, prompt: prompt)
                do {
                    if case .thread = session {
                        _ = try await tools.startCodeChannel(name: "fix")
                        continuation.yield(.text("Moved the task"))
                    } else {
                        do { try await tools.setTitle("Bug fix") }
                        catch { await probe.record(session, "rename failed") }
                        // Defend against a model using a stale tool definition after resuming.
                        let response = await AgentToolset.handle(.init(
                            arguments: ["name": "another"], callId: "call", threadId: "thread",
                            tool: AgentToolset.startCodeChannel, turnId: "turn",
                        ), tools: tools)
                        if case let .inputText(item)? = response.contentItems.first {
                            #expect(item.text.contains("Continue the requested work here"))
                        }
                        continuation.yield(.text("Working here"))
                        await probe.record(session, "continued")
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
