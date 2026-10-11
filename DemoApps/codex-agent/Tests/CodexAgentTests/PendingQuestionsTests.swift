@testable import CodexAgent
import SlackKit
import Testing

struct PendingQuestionsTests {
    let session = SessionKey(channel: "C1", threadTs: "1.0")

    @Test
    func `returns the option the person picked`() async throws {
        let questions = PendingQuestions()
        async let choice = questions.wait(id: "q", session: session, options: ["A", "B"], userId: "U1")
        try await answerWhenWaiting(questions) { await $0.answer(id: "q", index: 1, userId: "U1") == .accepted("B") }
        #expect(try await choice == "B")
    }

    @Test
    func `ignores answers from someone else and expired questions`() async throws {
        let questions = PendingQuestions()
        async let choice = questions.wait(id: "q", session: session, options: ["A", "B"], userId: "U1")
        try await answerWhenWaiting(questions) { await $0.answer(id: "q", index: 0, userId: "U2") == .notAsked(userId: "U1") }
        #expect(await questions.answer(id: "q", index: 0, userId: "U1") == .accepted("A"))
        #expect(try await choice == "A")
        #expect(await questions.answer(id: "q", index: 0, userId: "U1") == .expired)
    }

    @Test
    func `stopping the session ends its questions`() async throws {
        let questions = PendingQuestions()
        let waiting = Task { try await questions.wait(id: "q", session: session, options: ["A", "B"], userId: "U1") }
        try await answerWhenWaiting(questions) { questions in
            await questions.cancel(SessionKey(channel: "C1", threadTs: "1.0"))
            return true
        }
        await #expect(throws: AgentToolError.self) { try await waiting.value }
    }

    @Test
    func `times out`() async {
        let questions = PendingQuestions(timeout: .milliseconds(10))
        await #expect(throws: AgentToolError.self) {
            try await questions.wait(id: "q", session: session, options: ["A", "B"], userId: "U1")
        }
    }

    /// Retries `act` until the question is registered, since `wait` registers it asynchronously.
    private func answerWhenWaiting(
        _ questions: PendingQuestions,
        _ act: (PendingQuestions) async -> Bool,
    ) async throws {
        for _ in 0 ..< 1000 {
            if await questions.isWaiting(id: "q") {
                #expect(await act(questions))
                return
            }
            await Task.yield()
        }
        Issue.record("the question was never registered")
    }
}

struct QuestionBlocksTests {
    @Test
    func `gives every option button its own action_id`() {
        let blocks = SlackAgentTools.questionBlocks(id: "q", question: "Which?", options: ["A", "B", "C"], userId: "U1")
        guard case let .actions(actions)? = blocks.last else {
            Issue.record("expected an actions block")
            return
        }
        let buttons = actions.elements.compactMap { element -> ButtonElement? in
            guard case let .button(button) = element else { return nil }
            return button
        }
        #expect(buttons.map(\.actionId) == ["ask_user_choice_0", "ask_user_choice_1", "ask_user_choice_2"])
        #expect(Set(buttons.compactMap(\.actionId)).count == buttons.count)
        #expect(buttons.allSatisfy { $0.value == "q" })
    }
}
