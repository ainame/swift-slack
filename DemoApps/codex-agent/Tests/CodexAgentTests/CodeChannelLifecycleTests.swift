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
        #expect(producer.isSessionStopped)
        do { try await tools.publishView(.diff(content: "x")); Issue.record("Published after archive") } catch {}
        #expect(await slack.requests.count == 3)
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
