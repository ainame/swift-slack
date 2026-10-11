import Foundation

public struct CardBlock: Codable, Hashable, Sendable {
    public let type: String
    public let heroImage: ImageElement?
    public let icon: ImageElement?
    public let slackIcon: SlackIconObject?
    public let title: TextObject?
    public let subtitle: TextObject?
    public let body: TextObject?
    public let subtext: TextObject?
    public let actions: [ActionElementType]?
    public let blockId: String?

    public init(
        heroImage: ImageElement? = nil,
        icon: ImageElement? = nil,
        slackIcon: SlackIconObject? = nil,
        title: TextObject? = nil,
        subtitle: TextObject? = nil,
        body: TextObject? = nil,
        subtext: TextObject? = nil,
        actions: [ActionElementType]? = nil,
        blockId: String? = nil,
    ) {
        type = "card"
        self.heroImage = heroImage
        self.icon = icon
        self.slackIcon = slackIcon
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.subtext = subtext
        self.actions = actions
        self.blockId = blockId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case heroImage = "hero_image"
        case icon
        case slackIcon = "slack_icon"
        case title
        case subtitle
        case body
        case subtext
        case actions
        case blockId = "block_id"
    }
}
