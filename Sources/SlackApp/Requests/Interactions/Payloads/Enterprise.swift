/// The Enterprise organization an interaction happened in.
public struct Enterprise: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String?

    public init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
}
