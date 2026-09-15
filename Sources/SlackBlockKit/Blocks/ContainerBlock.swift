import Foundation

/// Groups child blocks with an optional title, icon, and collapse controls.
public struct ContainerBlock: Codable, Hashable, Sendable {
    public let type: String
    public let title: TextObject?
    public let richTextTitle: RichTextBlock?
    public let subtitle: TextObject?
    public let childBlocks: [Block]
    public let width: String?
    public let icon: ImageElement?
    public let isCollapsible: Bool?
    public let defaultCollapsed: Bool?
    public let hasHeaderDivider: Bool?
    public let blockId: String?

    public init(
        title: TextObject? = nil,
        richTextTitle: RichTextBlock? = nil,
        subtitle: TextObject? = nil,
        childBlocks: [Block] = [],
        width: String? = nil,
        icon: ImageElement? = nil,
        isCollapsible: Bool? = nil,
        defaultCollapsed: Bool? = nil,
        hasHeaderDivider: Bool? = nil,
        blockId: String? = nil,
    ) {
        type = "container"
        self.title = title
        self.richTextTitle = richTextTitle
        self.subtitle = subtitle
        self.childBlocks = childBlocks
        self.width = width
        self.icon = icon
        self.isCollapsible = isCollapsible
        self.defaultCollapsed = defaultCollapsed
        self.hasHeaderDivider = hasHeaderDivider
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case richTextTitle = "rich_text_title"
        case subtitle
        case childBlocks = "child_blocks"
        case width
        case icon
        case isCollapsible = "is_collapsible"
        case defaultCollapsed = "default_collapsed"
        case hasHeaderDivider = "has_header_divider"
        case blockId = "block_id"
    }
}
