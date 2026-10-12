import Codex
@testable import CodexAgent
import Foundation
import SlackKit
import Testing

struct CodingApprovalTests {
    @Test(.timeLimit(.minutes(1)), arguments: [0, 1])
    func `approval decision returns to Codex without cancelling the running turn`(choice: Int) async throws {
        let slack = FakeSlack()
        let questions = PendingQuestions()
        let producer = TurnProducer()
        let router = ToolRouter(writeWorkspace: "/tmp/code")
        router.tools = await tools(slack, questions: questions, producer: producer)
        let outcome = ApprovalOutcome()
        let production = Task {
            await producer.run {
                let decision = await router.approveCommand(.init(
                    threadID: "t", turnID: "v", itemID: "i", command: "swift test", workingDirectory: "/tmp/code",
                ))
                await outcome.record(decision: decision)
                try? await Task.sleep(for: .milliseconds(20))
                await outcome.record(cancelled: Task.isCancelled)
            }
        }
        await slack.waitFor("agentsSessionsSetStatus")
        let id = try await questionID(slack)
        #expect(await questions.answer(id: id, index: choice, userId: "U1") == .accepted(choice == 0 ? "Approve" : "Deny"))
        await production.value

        #expect(await outcome.decision == (choice == 0 ? .approve : .deny))
        #expect(await outcome.cancelled == false)
        #expect(producer.reason == nil)
    }

    @Test
    func `both Codex approval handlers deny by default and reject outside roots`() async {
        let tools = AcceptingTools()
        let readonly = ToolRouter()
        readonly.tools = tools
        let command = CommandApprovalRequest(threadID: "t", turnID: "v", itemID: "i", command: "swift test", workingDirectory: "/tmp/code")
        #expect(await readonly.approveCommand(command) == .deny)
        #expect(await readonly.approveFiles(.init(threadID: "t", turnID: "v", itemID: "i")) == .deny)
        let writable = ToolRouter(writeWorkspace: "/tmp/code")
        writable.tools = tools
        #expect(await writable.approveCommand(command) == .approve)
        #expect(await writable.approveFiles(.init(threadID: "t", turnID: "v", itemID: "i", grantRoot: "/tmp/code")) == .approve)
        #expect(await writable.approveFiles(.init(threadID: "t", turnID: "v", itemID: "i", grantRoot: "/tmp/other")) == .deny)
        var outside = command
        outside.workingDirectory = "/tmp/code/../other"
        #expect(await writable.approveCommand(outside) == .deny)
        outside.command = nil
        outside.workingDirectory = "/tmp/code"
        #expect(await writable.approveCommand(outside) == .deny)
        #expect(await tools.requests.count == 2)
        writable.tools = nil
        #expect(await writable.approveCommand(command) == .deny)
    }

    @Test(.timeLimit(.minutes(1)))
    func `only the person asked can approve a command`() async throws {
        let slack = FakeSlack()
        let questions = PendingQuestions()
        let tools = await tools(slack, questions: questions)
        let task = Task { await tools.approve(.command("swift test")) }
        await slack.waitFor("agentsSessionsSetStatus")
        let id = try await questionID(slack)
        #expect(await questions.answer(id: id, index: 0, userId: "someone-else") == .notAsked(userId: "U1"))
        #expect(await questions.answer(id: id, index: 0, userId: "U1") == .accepted("Approve"))
        #expect(await task.value)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `stops deny pending approvals without restoring Slack status`(external: Bool) async throws {
        let slack = FakeSlack()
        let questions = PendingQuestions()
        let producer = TurnProducer()
        let tools = await tools(slack, questions: questions, producer: producer)
        let task = Task { await tools.approve(.files("Update Sources/example.swift")) }
        await slack.waitFor("agentsSessionsSetStatus")
        if external {
            producer.stopSession()
        } else {
            producer.cancel()
        }
        #expect(await !task.value)
        #expect(await slack.requests("agentsSessionsSetStatus").map { $0["status"] } == ["suspended"])
        #expect(await slack.requests("chatUpdate").isEmpty)
        let id = try await questionID(slack)
        #expect(await !questions.isWaiting(id: id))
    }

    @Test
    func `approval details too long to show are denied without posting`() async {
        let slack = FakeSlack()
        let tools = await tools(slack, questions: PendingQuestions())
        #expect(await !tools.approve(.command(String(repeating: "x", count: 3000))))
        #expect(await slack.requests.isEmpty)
    }

    @Test
    func `timed out file approvals are denied`() async {
        let slack = FakeSlack()
        let tools = await tools(slack, questions: PendingQuestions(timeout: .zero))
        #expect(await !tools.approve(.files("Edit a file")))
    }

    private func tools(_ slack: FakeSlack, questions: PendingQuestions, producer: TurnProducer = .init()) async -> SlackAgentTools {
        await SlackAgentTools(
            client: slack.client(),
            session: .codeChannel(channel: "C1"),
            replyThreadTs: nil,
            userId: "U1",
            identity: nil,
            questions: questions,
            isTitledByUser: { false },
            producer: producer,
        )
    }

    private func questionID(_ slack: FakeSlack) async throws -> String {
        let blocks = try #require(await slack.requests("chatPostMessage").last?["blocks"])
        let json = try JSONSerialization.jsonObject(with: Data(blocks.utf8)) as? [[String: Any]]
        return try #require(json?.last?["block_id"] as? String)
    }
}

private actor ApprovalOutcome {
    private(set) var decision: ApprovalDecision?
    private(set) var cancelled: Bool?

    func record(decision: ApprovalDecision) { self.decision = decision }
    func record(cancelled: Bool) { self.cancelled = cancelled }
}

private actor AcceptingTools: AgentTools {
    var requests: [AgentApproval] = []
    func setTitle(_: String) async throws {}
    func readSlack(_: SlackReadScope, limit _: Int) async throws -> String {
        ""
    }

    func askUser(_: String, options _: [String]) async throws -> String {
        "Approve"
    }

    func approve(_ request: AgentApproval) async -> Bool {
        requests.append(request); return true
    }
}
