import SlackStreaming

/// Identifies one agent session: Slack scopes sessions to a single thread in a channel or DM.
struct SessionKey: Hashable, Sendable, CustomStringConvertible {
    let channel: String
    let threadTs: String

    var description: String {
        "\(channel)/\(threadTs)"
    }
}

enum AgentEvent: Sendable, Equatable {
    /// A task started or changed status.
    case task(TaskUpdate)
    /// More text for the answer, appended to what was streamed so far.
    case text(String)
}

/// Produces the agent's side of a turn. The Slack layer turns the events into streamed messages.
protocol AgentBackend: Sendable {
    /// Runs one turn for `prompt`, continuing the conversation already held for `session`.
    ///
    /// Cancelling the task that iterates the stream stops the turn.
    func respond(to prompt: String, in session: SessionKey) -> AsyncThrowingStream<AgentEvent, any Error>
}
