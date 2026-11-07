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

enum SlackReadScope: String, Sendable, Decodable {
    case thread
    case channel
}

/// A tool failure the agent should read, such as a refused rename or an unanswered question.
struct AgentToolError: Error, CustomStringConvertible {
    let description: String
}
