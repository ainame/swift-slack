import Foundation
import OpenAPIRuntime

/// One step shown in a streaming message, sent as a `task_update` chunk.
public struct TaskUpdate: Sendable, Equatable {
    public enum Status: String, Sendable {
        case inProgress = "in_progress"
        case complete
        case error
    }

    public var id: String
    public var title: String
    public var status: Status
    public var details: String?
    public var output: String?

    public init(id: String, title: String, status: Status, details: String? = nil, output: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.details = details
        self.output = output
    }
}

/// A chunk for the `chunks` argument of `chat.startStream`, `chat.appendStream`, and `chat.stopStream`.
///
/// swift-slack types `chunks` as an untyped array because its request bodies come from slack-api-ref, which
/// declares the argument without an item schema. This enum encodes the chunk objects the method references
/// describe.
public enum StreamChunk: Sendable, Equatable, Encodable {
    /// Markdown appended to the message text.
    case markdownText(String)
    /// A task card in `timeline` mode, or a task in the plan in `plan` mode.
    case taskUpdate(TaskUpdate)
    /// The title of the plan in `plan` mode.
    case planUpdate(title: String)

    /// The method references limit `markdown_text` to 12,000 characters.
    static let markdownTextLimit = 12000
    /// The method references limit `task_update` and `plan_update` fields to 256 characters.
    static let taskFieldLimit = 256

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case title
        case status
        case details
        case output
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .markdownText(text):
            try container.encode("markdown_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .taskUpdate(task):
            try container.encode("task_update", forKey: .type)
            try container.encode(task.id, forKey: .id)
            try container.encode(Self.truncated(task.title), forKey: .title)
            try container.encode(task.status.rawValue, forKey: .status)
            try container.encodeIfPresent(task.details.map(Self.truncated), forKey: .details)
            try container.encodeIfPresent(task.output.map(Self.truncated), forKey: .output)
        case let .planUpdate(title):
            try container.encode("plan_update", forKey: .type)
            try container.encode(Self.truncated(title), forKey: .title)
        }
    }

    private static func truncated(_ value: String) -> String {
        value.count > taskFieldLimit ? value.prefix(taskFieldLimit - 1) + "…" : value
    }

    /// Converts chunks to the untyped container the generated request bodies take, or `nil` when empty.
    static func container(for chunks: [StreamChunk]) throws -> OpenAPIArrayContainer? {
        guard !chunks.isEmpty else { return nil }
        return try JSONDecoder().decode(OpenAPIArrayContainer.self, from: JSONEncoder().encode(chunks))
    }
}
