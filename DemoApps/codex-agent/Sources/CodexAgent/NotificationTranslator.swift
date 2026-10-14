import Codex
import SlackKit

/// Maps Codex app-server notifications onto agent events.
struct NotificationTranslator {
    enum Failure: Error, CustomStringConvertible {
        case turnFailed(String)

        var description: String {
            switch self {
            case let .turnFailed(message): message
            }
        }
    }

    let turnID: String
    /// The turn's error, kept until the turn completes so the caller still reads it to the end.
    private(set) var failure: Failure?
    private var lastMessageItemID: String?
    /// Messages that streamed deltas. Codex sometimes sends a message only as a completed item.
    private var streamedMessageIDs: Set<String> = []

    init(turnID: String) {
        self.turnID = turnID
    }

    /// Maps one notification. `turnID` is the notification's turn, or `nil` for one that belongs to none.
    mutating func events(turnID notificationTurnID: String?, payload: CodexNotificationPayload) -> [AgentEvent] {
        guard notificationTurnID == nil || notificationTurnID == turnID else {
            return []
        }

        switch payload {
        case let .agentMessageDelta(payload):
            streamedMessageIDs.insert(payload.itemId)
            return [text(payload.delta, inMessage: payload.itemId)]
        case let .turnDiffUpdated(payload):
            return [.diff(payload.diff)]
        case let .itemCompleted(payload):
            if case let .agentMessage(message) = payload.item, !streamedMessageIDs.contains(message.id) {
                return message.text.isEmpty ? [] : [text(message.text, inMessage: message.id)]
            }
            var events = task(for: payload.item).map { [AgentEvent.task($0)] } ?? []
            if case let .dynamicToolCall(call) = payload.item, let cards = AgentToolset.cards(from: call) {
                events.append(.cards(cards))
            }
            return events
        case let .itemStarted(payload):
            return task(for: payload.item).map { [.task($0)] } ?? []
        case let .turnCompleted(payload) where payload.turn.status == .failed:
            failure = failure ?? .turnFailed(payload.turn.error?.message ?? "Codex turn failed")
            return []
        case let .error(payload):
            failure = failure ?? .turnFailed(payload.error.message)
            return []
        default:
            return []
        }
    }

    /// Separates the messages Codex writes between tool calls into paragraphs.
    private mutating func text(_ text: String, inMessage itemID: String) -> AgentEvent {
        let separator = lastMessageItemID.map { $0 == itemID ? "" : "\n\n" } ?? ""
        lastMessageItemID = itemID
        return .text(separator + text)
    }

    private func task(for item: ThreadItem) -> TaskUpdate? {
        switch item {
        case let .commandExecution(command):
            TaskUpdate(
                id: command.id,
                title: "Run `\(command.command)`",
                status: status(command.status),
                output: command.aggregatedOutput.flatMap { $0.isEmpty ? nil : String($0.suffix(200)) },
            )
        case let .webSearch(search):
            // The query is empty until the search completes.
            TaskUpdate(
                id: search.id,
                title: search.query.isEmpty ? "Search the web" : "Search the web for \"\(search.query)\"",
                status: .complete,
            )
        case let .fileChange(change):
            TaskUpdate(
                id: change.id,
                title: "Edit \(change.changes.count) file(s)",
                status: status(change.status),
                details: change.changes.map(\.path).joined(separator: "\n"),
            )
        case let .dynamicToolCall(call):
            TaskUpdate(id: call.id, title: AgentToolset.title(for: call.tool), status: status(call), details: failureDetails(call))
        case let .mcpToolCall(call):
            TaskUpdate(id: call.id, title: "Call \(call.server)/\(call.tool)", status: status(call.status))
        case let .reasoning(reasoning):
            (reasoning.summary ?? []).isEmpty
                ? nil
                : TaskUpdate(
                    id: reasoning.id,
                    title: "Think",
                    status: .complete,
                    details: reasoning.summary?.joined(separator: "\n"),
                )
        default:
            nil
        }
    }

    private func status(_ status: CommandExecutionStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }

    private func status(_ status: PatchApplyStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }

    private func failureDetails(_ call: DynamicToolCallThreadItem) -> String? {
        guard status(call) == .error else { return nil }
        let text = (call.contentItems ?? []).compactMap { item -> String? in
            guard case let .inputText(item) = item else { return nil }
            return item.text
        }.joined(separator: "\n")
        return text.isEmpty ? nil : String(text.prefix(2000))
    }

    private func status(_ call: DynamicToolCallThreadItem) -> TaskUpdate.Status {
        switch call.status {
        case .inProgress: .inProgress
        case .completed where call.success != false: .complete
        default: .error
        }
    }

    private func status(_ status: McpToolCallStatus) -> TaskUpdate.Status {
        switch status {
        case .inProgress: .inProgress
        case .completed: .complete
        default: .error
        }
    }
}
