import Foundation

/// Displays a task's status, rich-text details and output, and source links.
public struct TaskCardBlock: Codable, Hashable, Sendable {
    public let type: String
    public let taskId: String
    public let title: String
    public let status: String
    public let details: RichTextBlock?
    public let output: RichTextBlock?
    public let sources: [URLSourceElement]?
    public let blockId: String?
    public let icon: SlackIconObject?
    public let hideTitle: Bool?

    public init(
        taskId: String,
        title: String,
        status: String,
        details: RichTextBlock? = nil,
        output: RichTextBlock? = nil,
        sources: [URLSourceElement]? = nil,
        blockId: String? = nil,
        icon: SlackIconObject? = nil,
        hideTitle: Bool? = nil,
    ) {
        type = "task_card"
        self.taskId = taskId
        self.title = title
        self.status = status
        self.details = details
        self.output = output
        self.sources = sources
        self.blockId = blockId
        self.icon = icon
        self.hideTitle = hideTitle
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case taskId = "task_id"
        case title
        case status
        case details
        case output
        case sources
        case blockId = "block_id"
        case icon
        case hideTitle = "hide_title"
    }
}
