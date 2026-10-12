import Codex
@testable import CodexAgent
import Foundation
import Testing

struct AgentToolsetTests {
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
        let tools = FakeTools()
        #expect(await handle("show_cards", ["cards": [["title": "A"]]], tools).success)

        let invalid = await handle("show_cards", ["cards": []], tools)
        #expect(!invalid.success)
        #expect(text(invalid) == "Give at least one card a title or a body.")
    }

    @Test
    func `renames through the tools, and reports a refused rename`() async {
        let tools = FakeTools()
        #expect(await handle("set_title", ["title": "Release notes"], tools).success)
        #expect(await tools.titles == ["Release notes"])

        let refused = await handle("set_title", ["title": "Other"], FakeTools(refusesTitle: true))
        #expect(!refused.success)
        #expect(text(refused) == "The person named this conversation; keep their title.")
    }

    @Test
    func `reads the conversation with a clamped limit`() async {
        let tools = FakeTools()
        let reply = await handle("read_slack", ["scope": "channel", "limit": 500], tools)
        #expect(reply.success)
        #expect(text(reply) == "channel:50")
    }

    @Test
    func `returns the person's choice`() async {
        let reply = await handle("ask_user", ["question": "Which?", "options": ["A", "B"]], FakeTools())
        #expect(text(reply) == "The person chose: B")
    }

    @Test(arguments: [
        ("ask_user", ["question": "Which?", "options": ["only one"]] as JSONValue),
        ("read_slack", ["scope": "everywhere"] as JSONValue),
        ("rm_rf", [:] as JSONValue),
    ])
    func `rejects invalid calls`(tool: String, arguments: JSONValue) async {
        #expect(await !handle(tool, arguments, FakeTools()).success)
    }

    @Test
    func `reads cards only from successful show_cards calls`() {
        let arguments: JSONValue = ["cards": [["title": "A"]]]
        #expect(AgentToolset.cards(from: item(arguments, success: true)) == SlackUI(cards: [.init(title: "A")]))
        #expect(AgentToolset.cards(from: item(arguments, success: false)) == nil)
        #expect(AgentToolset.cards(from: item(arguments, success: true, tool: "set_title")) == nil)
    }

    private func handle(_ tool: String, _ arguments: JSONValue, _ tools: FakeTools) async -> DynamicToolCallResponse {
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

private actor FakeTools: AgentTools {
    private(set) var titles: [String] = []
    private let refusesTitle: Bool

    init(refusesTitle: Bool = false) {
        self.refusesTitle = refusesTitle
    }

    func setTitle(_ title: String) async throws {
        if refusesTitle {
            throw AgentToolError(description: "The person named this conversation; keep their title.")
        }
        titles.append(title)
    }

    func readSlack(_ scope: SlackReadScope, limit: Int) async throws -> String {
        "\(scope.rawValue):\(limit)"
    }

    func askUser(_: String, options: [String]) async throws -> String {
        options.last ?? ""
    }
}
