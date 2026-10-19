import Codex
@testable import CodexAgent
import Foundation
import Testing

struct AgentToolsetTests {
    let slack = FakeSlack()
    let questions = PendingQuestions()

    @Test
    func `registers conversation and code channel tools`() {
        let names = AgentToolset.specs.compactMap { spec -> String? in
            guard case let .function(function) = spec else { return nil }
            return function.name
        }
        #expect(names == [
            "show_cards",
            "set_title",
            "read_slack",
            "ask_user",
            "upload_file",
            "start_code_channel",
            "publish_code_view",
            "archive_code_channel",
        ])
    }

    @Test
    func `code channel threads cannot start another code channel`() {
        let names = AgentToolset.specs(for: .codeChannel(channel: "CODE")).compactMap { spec -> String? in
            guard case let .function(function) = spec else { return nil }
            return function.name
        }
        #expect(!names.contains("start_code_channel"))
        #expect(names.contains("publish_code_view"))
        #expect(names.contains("archive_code_channel"))
        #expect(names.contains("set_title"))
    }

    @Test
    func `checks show_cards arguments and tells the agent what to fix`() async {
        let tools = await tools()
        #expect(await handle("show_cards", ["cards": [["title": "A"]]], tools).success)

        let invalid = await handle("show_cards", ["cards": []], tools)
        #expect(!invalid.success)
        #expect(text(invalid) == "Give at least one card a title or a body.")
    }

    @Test
    func `renames through the tools, and reports a refused rename`() async {
        let tools = await tools()
        #expect(await handle("set_title", ["title": "Release notes"], tools).success)
        #expect(await slack.requests("agentsSessionsRename").map { $0["title"] } == ["Release notes"])

        let locked = await self.tools(titledByUser: true)
        let refused = await handle("set_title", ["title": "Other"], locked)
        #expect(!refused.success)
        #expect(text(refused) == "The person named this conversation; keep their title.")
        #expect(await slack.requests("agentsSessionsRename").count == 1)
    }

    @Test
    func `reads the conversation with a clamped limit`() async throws {
        await slack.reply(to: "conversationsHistory", with: .json(#"{"ok":true,"messages":[{"text":"Earlier discussion","user":"U2","ts":"1.0"}]}"#))
        let tools = await tools()
        let reply = await handle("read_slack", ["scope": "channel", "limit": 500], tools)
        #expect(reply.success)
        #expect(text(reply) == "<@U2>: Earlier discussion")
        let request = try #require(await slack.requests("conversationsHistory").first)
        #expect(Double(request["limit"] ?? "") == 50)
        #expect(request["channel"] == "C1")
    }

    @Test(.timeLimit(.minutes(1)))
    func `returns the person's choice`() async throws {
        let tools = await tools()
        let asking = Task { await handle("ask_user", ["question": "Which?", "options": ["A", "B"]], tools) }
        defer { asking.cancel() }
        await slack.waitFor("agentsSessionsSetStatus") { $0["status"] == "suspended" }
        let id = try await pendingQuestionID(in: slack, questions: questions)
        #expect(await questions.answer(id: id, index: 1, userId: "U1") == .accepted("B"))
        #expect(await text(asking.value) == "The person chose: B")
    }

    @Test(arguments: [
        ("ask_user", ["question": "Which?", "options": ["only one"]] as JSONValue),
        ("read_slack", ["scope": "everywhere"] as JSONValue),
        ("rm_rf", [:] as JSONValue),
    ])
    func `rejects invalid calls`(tool: String, arguments: JSONValue) async {
        let tools = await tools()
        #expect(await !handle(tool, arguments, tools).success)
    }

    @Test
    func `reads cards only from successful show_cards calls`() {
        let arguments: JSONValue = ["cards": [["title": "A"]]]
        #expect(AgentToolset.cards(from: item(arguments, success: true)) == SlackUI(cards: [.init(title: "A")]))
        #expect(AgentToolset.cards(from: item(arguments, success: false)) == nil)
        #expect(AgentToolset.cards(from: item(arguments, success: true, tool: "set_title")) == nil)
    }

    private func tools(titledByUser: Bool = false) async -> SlackAgentTools {
        await SlackAgentTools(
            client: slack.client(), session: .thread(channel: "C1", threadTs: "1.0"), replyThreadTs: "1.0",
            userId: "U1", identity: nil, questions: questions, isTitledByUser: { titledByUser }, producer: .init(),
        )
    }

    private func handle(_ tool: String, _ arguments: JSONValue, _ tools: SlackAgentTools) async -> DynamicToolCallResponse {
        await AgentToolset.handle(
            DynamicToolCallParams(arguments: arguments, callId: "call-1", threadId: "thread", tool: tool, turnId: "turn"),
            tools: tools,
        )
    }

    private func text(_ response: DynamicToolCallResponse) -> String? {
        guard case let .inputText(item)? = response.contentItems.first else { return nil }
        return item.text
    }

    private func item(_ arguments: JSONValue, success: Bool, tool: String = "show_cards") -> DynamicToolCallThreadItem {
        DynamicToolCallThreadItem(
            arguments: arguments,
            id: "call-1",
            status: success ? .completed : .failed,
            success: success,
            tool: tool,
            type: .dynamicToolCall,
        )
    }
}
