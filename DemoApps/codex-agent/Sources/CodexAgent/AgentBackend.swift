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
    /// Cards to show under the answer, from the agent's `show_cards` tool.
    case cards(SlackUI)
}

/// Slack actions an agent can take during a turn, offered to it as tools. Each turn gets its own,
/// scoped to the turn's session and the person it answers.
protocol AgentTools: Sendable {
    /// Renames the agent session. Throws ``AgentToolError`` when the person has named it themselves.
    func setTitle(_ title: String) async throws

    /// Returns recent messages from the session's thread, or from its channel, as text.
    func readSlack(_ scope: SlackReadScope, limit: Int) async throws -> String

    /// Asks the person to pick one of `options` and returns their choice.
    func askUser(_ question: String, options: [String]) async throws -> String
}

enum SlackReadScope: String, Sendable, Decodable {
    case thread
    case channel
}

/// A tool failure the agent should read, such as a refused rename or an unanswered question.
struct AgentToolError: Error, CustomStringConvertible {
    let description: String
}

/// Produces the agent's side of a turn. The Slack layer turns the events into streamed messages.
protocol AgentBackend: Sendable {
    /// Runs one turn for `prompt`, continuing the conversation already held for `session`.
    ///
    /// Cancelling the task that iterates the stream stops the turn.
    func respond(
        to prompt: String,
        in session: SessionKey,
        tools: any AgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error>
}
