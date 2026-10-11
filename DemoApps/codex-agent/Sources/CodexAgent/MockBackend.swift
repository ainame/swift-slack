import SlackStreaming

/// Replays a scripted turn so the Slack side can be tried without the Codex CLI.
struct MockBackend: AgentBackend {
    func respond(to prompt: String, in _: SessionKey) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await play(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stopping cancels the stream's task, which ends the scripted turn at its next pause.
    func interrupt(_: SessionKey) async {}

    private func play(prompt: String, continuation: AsyncThrowingStream<AgentEvent, any Error>.Continuation) async throws {
        let steps = [
            ("read", "Read the request"),
            ("search", "Look for relevant context"),
            ("compose", "Compose the answer"),
        ]
        for (id, title) in steps {
            continuation.yield(.task(TaskUpdate(id: id, title: title, status: .inProgress)))
            try await Task.sleep(for: .seconds(1))
            continuation.yield(.task(TaskUpdate(id: id, title: title, status: .complete)))
        }

        let answer = """
        This is the *mock* backend, so I did not really think about it. You asked:

        > \(prompt)

        Set `AGENT_BACKEND=codex` to answer with Codex instead.
        """
        for word in answer.split(separator: " ", omittingEmptySubsequences: false) {
            continuation.yield(.text(word + " "))
            try await Task.sleep(for: .milliseconds(80))
        }
    }
}
