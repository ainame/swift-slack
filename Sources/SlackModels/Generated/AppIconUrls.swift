@_spi(Generated) import OpenAPIRuntime
#if os(Linux)
@preconcurrency import struct Foundation.Data
@preconcurrency import struct Foundation.Date
@preconcurrency import struct Foundation.URL
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
#endif

/// - Remark: Generated from `#/components/schemas/AppIconUrls`.
public struct AppIconUrls: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_1024`.
    public var image1024: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_128`.
    public var image128: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_192`.
    public var image192: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_32`.
    public var image32: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_36`.
    public var image36: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_48`.
    public var image48: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_512`.
    public var image512: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_64`.
    public var image64: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_72`.
    public var image72: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_96`.
    public var image96: Swift.String?
    /// - Remark: Generated from `#/components/schemas/AppIconUrls/image_original`.
    public var imageOriginal: Swift.String?
    /// Creates a new `AppIconUrls`.
    ///
    /// - Parameters:
    ///   - image1024:
    ///   - image128:
    ///   - image192:
    ///   - image32:
    ///   - image36:
    ///   - image48:
    ///   - image512:
    ///   - image64:
    ///   - image72:
    ///   - image96:
    ///   - imageOriginal:
    public init(
        image1024: Swift.String? = nil,
        image128: Swift.String? = nil,
        image192: Swift.String? = nil,
        image32: Swift.String? = nil,
        image36: Swift.String? = nil,
        image48: Swift.String? = nil,
        image512: Swift.String? = nil,
        image64: Swift.String? = nil,
        image72: Swift.String? = nil,
        image96: Swift.String? = nil,
        imageOriginal: Swift.String? = nil,
    ) {
        self.image1024 = image1024
        self.image128 = image128
        self.image192 = image192
        self.image32 = image32
        self.image36 = image36
        self.image48 = image48
        self.image512 = image512
        self.image64 = image64
        self.image72 = image72
        self.image96 = image96
        self.imageOriginal = imageOriginal
    }

    public enum CodingKeys: String, CodingKey {
        case image1024 = "image_1024"
        case image128 = "image_128"
        case image192 = "image_192"
        case image32 = "image_32"
        case image36 = "image_36"
        case image48 = "image_48"
        case image512 = "image_512"
        case image64 = "image_64"
        case image72 = "image_72"
        case image96 = "image_96"
        case imageOriginal = "image_original"
    }
}
