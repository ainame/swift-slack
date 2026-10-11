import SlackKit

/// Replays a scripted turn so the Slack side can be tried without the Codex CLI.
struct MockBackend: AgentBackend {
    func respond(
        to prompt: String,
        in _: SessionKey,
        tools: any AgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await play(prompt: prompt, tools: tools, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func play(
        prompt: String,
        tools: any AgentTools,
        continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
    ) async throws {
        // The same tools the codex backend offers Codex, shown as tasks.
        let messages = try await step("read", "Read the conversation", continuation) {
            try await tools.readSlack(.thread, limit: 10)
        }
        let choice = try await step("ask", "Ask you a question", continuation) {
            try await tools.askUser("Which part of the agent should I describe?", options: ["Streaming", "Sessions"])
        }
        _ = try await step("title", "Rename the conversation", continuation) {
            try await tools.setTitle("Mock: \(choice ?? prompt)")
            return ""
        }

        let answer = """
        This is the *mock* backend, so I did not really think about it. You asked:

        > \(prompt)

        I read \(messages?.split(separator: "\n\n").count ?? 0) messages in this thread\
        \(choice.map { ", and you chose *\($0)*" } ?? ""). Set `AGENT_BACKEND=codex` to answer with Codex instead.
        """
        for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
            continuation.yield(.text(word + " "))
            try await Task.sleep(for: .milliseconds(80))
        }

        // What the codex backend sends when Codex calls its show_cards tool.
        continuation.yield(.cards(SlackUI(cards: [
            .init(
                title: "Codex",
                subtitle: "openai/codex",
                body: "The coding agent behind the codex backend.",
                url: "https://github.com/openai/codex",
            ),
            .init(
                title: "Agent sessions",
                body: "How Slack shows status, titles, and the stop button.",
                url: "https://docs.slack.dev/ai/agent-sessions",
                ask: "How does the stop button work?",
            ),
        ])))
    }

    /// Runs one tool call as a task. A tool error, such as a refused rename, marks the task as failed and
    /// lets the turn go on, as Codex would after a failed tool call.
    private func step(
        _ id: String,
        _ title: String,
        _ continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation,
        _ operation: () async throws -> String,
    ) async throws -> String? {
        continuation.yield(.task(TaskUpdate(id: id, title: title, status: .inProgress)))
        do {
            let result = try await operation()
            continuation.yield(.task(TaskUpdate(id: id, title: title, status: .complete)))
            return result
        } catch let error as AgentToolError {
            continuation.yield(.task(TaskUpdate(id: id, title: title, status: .error, output: error.description)))
            return nil
        }
    }
}
