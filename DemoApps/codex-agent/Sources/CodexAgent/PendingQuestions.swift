import Foundation

/// Questions from `ask_user` waiting for a click.
actor PendingQuestions {
    private struct Question {
        let session: SessionKey
        let options: [String]
        let userId: String
        let continuation: CheckedContinuation<String, any Error>
        let timer: Task<Void, Never>
    }

    private let timeout: Duration
    private var questions: [String: Question] = [:]

    init(timeout: Duration = .seconds(600)) {
        self.timeout = timeout
    }

    /// Waits until the person picks an option, the question times out, or its session is stopped.
    ///
    /// `isCancelled` reports a stop that ``cancel(_:)`` handled before this question was registered.
    func wait(
        id: String,
        session: SessionKey,
        options: [String],
        userId: String,
        isCancelled: @Sendable () -> Bool = { false },
    ) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self.finish(id, with: .failure(AgentToolError(description: "The person did not answer.")))
                }
                questions[id] = Question(
                    session: session,
                    options: options,
                    userId: userId,
                    continuation: continuation,
                    timer: timer,
                )
                if isCancelled() {
                    finish(id, with: .failure(AgentToolError(description: "The person stopped the turn.")))
                    return
                }
            }
        } onCancel: {
            Task { await self.finish(id, with: .failure(CancellationError())) }
        }
    }

    enum Answer: Equatable {
        case accepted(String)
        /// Someone other than the person asked tried to answer.
        case notAsked(userId: String)
        /// The question was answered, timed out, or stopped already.
        case expired
    }

    /// Records a click on option `index` of question `id`.
    func answer(id: String, index: Int, userId: String) -> Answer {
        guard let question = questions[id], question.options.indices.contains(index) else {
            return .expired
        }
        guard question.userId == userId else {
            return .notAsked(userId: question.userId)
        }
        let choice = question.options[index]
        finish(id, with: .success(choice))
        return .accepted(choice)
    }

    func isWaiting(id: String) -> Bool {
        questions[id] != nil
    }

    /// Ends the questions of a stopped session, so the waiting tool call returns.
    func cancel(_ session: SessionKey) {
        for (id, question) in questions where question.session == session {
            finish(id, with: .failure(AgentToolError(description: "The person stopped the turn.")))
        }
    }

    private func finish(_ id: String, with result: Result<String, any Error>) {
        guard let question = questions.removeValue(forKey: id) else { return }
        question.timer.cancel()
        question.continuation.resume(with: result)
    }
}
