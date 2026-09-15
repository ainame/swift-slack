import SlackBlockKit

extension ContainerBlock: BlockComponent {
    public init(
        title: TextObject? = nil,
        richTextTitle: RichTextBlock? = nil,
        subtitle: TextObject? = nil,
        width: String? = nil,
        icon: ImageElement? = nil,
        isCollapsible: Bool? = nil,
        defaultCollapsed: Bool? = nil,
        hasHeaderDivider: Bool? = nil,
        blockId: String? = nil,
        @BlockBuilder childBlocks: () -> [Block],
    ) {
        self.init(
            title: title, richTextTitle: richTextTitle, subtitle: subtitle,
            childBlocks: childBlocks(), width: width, icon: icon,
            isCollapsible: isCollapsible, defaultCollapsed: defaultCollapsed,
            hasHeaderDivider: hasHeaderDivider, blockId: blockId,
        )
    }

    public func render() -> Block {
        .container(self)
    }
}

extension TaskCardBlock: BlockComponent {
    public func render() -> Block {
        .taskCard(self)
    }
}
