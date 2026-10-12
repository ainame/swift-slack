import SlackKit

/// Identifies one agent session. Slack scopes a session to a thread in a channel or DM, or, in a Slack Code
/// channel, to the whole channel: its top-level messages and their threads share one session.
enum SessionKey: Hashable, Sendable, CustomStringConvertible {
    case thread(channel: String, threadTs: String)
    case codeChannel(channel: String)

    var channel: String {
        switch self {
        case let .thread(channel, _), let .codeChannel(channel): channel
        }
    }

    /// The `thread_ts` that the `agents.sessions.*` methods take, or `nil` for a code channel's session.
    var threadTs: String? {
        switch self {
        case let .thread(_, threadTs): threadTs
        case .codeChannel: nil
        }
    }

    var description: String {
        switch self {
        case let .thread(channel, threadTs): "\(channel)/\(threadTs)"
        case let .codeChannel(channel): channel
        }
    }
}

typealias TaskUpdate = StreamingMessage.TaskUpdate

enum AgentEvent: Sendable, Equatable {
    /// The current aggregate unified diff for the turn.
    case diff(String)
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
    func startCodeChannel(name: String) async throws -> String
    func publishView(_ view: CodeChannel.View) async throws
    func archiveCodeChannel(summary: String) async throws
    func approve(_ request: AgentApproval) async -> Bool
    /// Renames the agent session. Throws ``AgentToolError`` when the person has named it themselves.
    func setTitle(_ title: String) async throws

    /// Returns recent messages from the conversation being answered, or from its channel, as text.
    func readSlack(_ scope: SlackReadScope, limit: Int) async throws -> String

    /// Asks the person to pick one of `options` and returns their choice.
    func askUser(_ question: String, options: [String]) async throws -> String
}

enum AgentApproval: Sendable, Equatable {
    case command(String)
    case files(String)

    var question: String {
        switch self {
        case let .command(details): "Approve this command?\n\(details)"
        case let .files(details): "Approve these file changes?\n\(details)"
        }
    }
}

extension AgentTools {
    func startCodeChannel(name _: String) async throws -> String {
        throw AgentToolError(description: "Code channels are unavailable in this backend.")
    }

    func publishView(_: CodeChannel.View) async throws {
        throw AgentToolError(description: "Code channel views are unavailable in this backend.")
    }

    func archiveCodeChannel(summary _: String) async throws {
        throw AgentToolError(description: "Code channels are unavailable in this backend.")
    }

    func approve(_: AgentApproval) async -> Bool {
        false
    }
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
