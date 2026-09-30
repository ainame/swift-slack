import Foundation

/// Icon URLs of a Slack app or app workflow.
///
/// Mirrors `com.slack.api.model.admin.AppIcons` in java-slack-sdk.
public struct AppIcons: Codable, Hashable, Sendable {
    public var image32: Swift.String?
    public var image36: Swift.String?
    public var image48: Swift.String?
    public var image64: Swift.String?
    public var image72: Swift.String?
    public var image96: Swift.String?
    public var image128: Swift.String?
    public var image192: Swift.String?
    public var image512: Swift.String?
    public var image1024: Swift.String?
    public var imageOriginal: Swift.String?

    public init(
        image32: Swift.String? = nil,
        image36: Swift.String? = nil,
        image48: Swift.String? = nil,
        image64: Swift.String? = nil,
        image72: Swift.String? = nil,
        image96: Swift.String? = nil,
        image128: Swift.String? = nil,
        image192: Swift.String? = nil,
        image512: Swift.String? = nil,
        image1024: Swift.String? = nil,
        imageOriginal: Swift.String? = nil,
    ) {
        self.image32 = image32
        self.image36 = image36
        self.image48 = image48
        self.image64 = image64
        self.image72 = image72
        self.image96 = image96
        self.image128 = image128
        self.image192 = image192
        self.image512 = image512
        self.image1024 = image1024
        self.imageOriginal = imageOriginal
    }

    private enum CodingKeys: String, CodingKey {
        case image32 = "image_32"
        case image36 = "image_36"
        case image48 = "image_48"
        case image64 = "image_64"
        case image72 = "image_72"
        case image96 = "image_96"
        case image128 = "image_128"
        case image192 = "image_192"
        case image512 = "image_512"
        case image1024 = "image_1024"
        case imageOriginal = "image_original"
    }
}
