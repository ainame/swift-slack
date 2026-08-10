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

/// - Remark: Generated from `#/components/schemas/Data`.
public struct TabData: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Data/file_id`.
    public var fileId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Data/folder_bookmark_id`.
    public var folderBookmarkId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Data/shared_ts`.
    public var sharedTs: Swift.String?
    /// Creates a new `Data`.
    ///
    /// - Parameters:
    ///   - fileId:
    ///   - folderBookmarkId:
    ///   - sharedTs:
    public init(
        fileId: Swift.String? = nil,
        folderBookmarkId: Swift.String? = nil,
        sharedTs: Swift.String? = nil,
    ) {
        self.fileId = fileId
        self.folderBookmarkId = folderBookmarkId
        self.sharedTs = sharedTs
    }

    public enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case folderBookmarkId = "folder_bookmark_id"
        case sharedTs = "shared_ts"
    }
}
