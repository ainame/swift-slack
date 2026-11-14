/// Displays a collection of related tasks under a plain-text title.
public struct PlanBlock: Codable, Hashable, Sendable {
    public let type: String
    public let title: String
    /// Up to 50 tasks, each with a unique task ID.
    public let tasks: [Task]
    public let blockId: String?

    public init(title: String, tasks: [Task], blockId: String? = nil) {
        type = "plan"
        self.title = title
        self.tasks = tasks
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case tasks
        case blockId = "block_id"
    }

    /// A task embedded in a plan. Slack omits the block discriminator here.
    public struct Task: Codable, Hashable, Sendable {
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
}
