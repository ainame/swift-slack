#if WebAPI_Chat
import SlackBlockKit

/// Types for ``APIProtocol/streamMessage(_:channel:threadTs:recipient:taskDisplay:blocks:sessionStatus:minimumInterval:isolation:)``,
/// which streams a message into a thread with `chat.startStream`, `chat.appendStream`, and `chat.stopStream`.
public enum StreamingMessage {
    /// One piece of a streaming message, sent as one of the `chunks` the streaming methods take.
    public enum Part: Sendable, Hashable {
        /// Markdown appended to the message text.
        case markdown(String)
        /// A task card in ``TaskDisplay/timeline`` mode, or a task in the plan in ``TaskDisplay/plan`` mode.
        /// Send the same ``TaskUpdate/id`` again to update the task.
        case task(TaskUpdate)
        /// The title of the plan in ``TaskDisplay/plan`` mode.
        case plan(title: String)
        /// Block Kit blocks streamed into the message.
        case blocks([Block])
    }

    /// A task shown in a streaming message, sent as a `task_update` chunk.
    ///
    /// Slack limits each text field to 256 characters, so longer values are truncated with an ellipsis.
    public struct TaskUpdate: Sendable, Hashable {
        public var id: String
        public var title: String
        public var status: Status
        public var details: String?
        public var output: String?
        public var sources: [Source]?

        public init(
            id: String,
            title: String,
            status: Status,
            details: String? = nil,
            output: String? = nil,
            sources: [Source]? = nil,
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.details = details
            self.output = output
            self.sources = sources
        }

        /// A task's status. Use ``init(rawValue:)`` for a status Slack adds later.
        public struct Status: RawRepresentable, Sendable, Hashable {
            public static let inProgress = Status(rawValue: "in_progress")
            public static let complete = Status(rawValue: "complete")
            public static let error = Status(rawValue: "error")

            public var rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        /// A link shown with a task.
        public struct Source: Sendable, Hashable {
            public var text: String
            public var url: String

            public init(text: String, url: String) {
                self.text = text
                self.url = url
            }
        }
    }

    /// The user a streaming reply is for. Slack requires it when streaming into a channel rather than a DM
    /// with the app.
    public struct Recipient: Sendable, Hashable {
        public var userId: String
        public var teamId: String

        public init(userId: String, teamId: String) {
            self.userId = userId
            self.teamId = teamId
        }
    }

    /// How a streaming message shows ``Part/task(_:)`` parts.
    public enum TaskDisplay: String, Sendable, Hashable {
        /// Each task renders as a card between the text around it.
        case timeline
        /// All tasks render together in one plan block.
        case plan
    }

    /// A streaming method that Slack answered with `"ok": false`.
    public struct Error: Swift.Error, Sendable, Hashable, CustomStringConvertible {
        /// The method that failed, such as `chat.appendStream`.
        public var method: String
        /// Slack's error code, such as `message_not_in_streaming_state`.
        public var code: String

        public init(method: String, code: String) {
            self.method = method
            self.code = code
        }

        public var description: String {
            "\(method) failed: \(code)"
        }
    }
}
#endif
