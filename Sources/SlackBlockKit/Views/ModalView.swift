import Foundation

public struct ModalView: Codable, Hashable, Sendable {
    public let type: String
    public let title: TextObject
    public let blocks: [Block]
    public let close: TextObject?
    public let submit: TextObject?
    public let privateMetadata: String?
    public let callbackId: String?
    public let clearOnClose: Bool?
    public let notifyOnClose: Bool?
    public let externalId: String?
    public let submitDisabled: Bool?
    public let state: StateValuesObject?
    public let id: String?
    public let hash: String?

    public init(
        title: TextObject,
        blocks: [Block],
        close: TextObject? = nil,
        submit: TextObject? = nil,
        privateMetadata: String? = nil,
        callbackId: String? = nil,
        clearOnClose: Bool? = nil,
        notifyOnClose: Bool? = nil,
        externalId: String? = nil,
        submitDisabled: Bool? = nil,
        state: StateValuesObject? = nil,
        id: String? = nil,
        hash: String? = nil,
    ) {
        type = "modal"
        self.title = title
        self.blocks = blocks
        self.close = close
        self.submit = submit
        self.privateMetadata = privateMetadata
        self.callbackId = callbackId
        self.clearOnClose = clearOnClose
        self.notifyOnClose = notifyOnClose
        self.externalId = externalId
        self.submitDisabled = submitDisabled
        self.state = state
        self.id = id
        self.hash = hash
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case blocks
        case close
        case submit
        case privateMetadata = "private_metadata"
        case callbackId = "callback_id"
        case clearOnClose = "clear_on_close"
        case notifyOnClose = "notify_on_close"
        case externalId = "external_id"
        case submitDisabled = "submit_disabled"
        case state
        case id
        case hash
    }

    // Slack sends `id`, `state`, and `hash` in views but rejects them inside the `view` argument of `views.*` methods
    // and acknowledgements, so they're decoded but not encoded. `views.update` takes the ID and `hash` as separate
    // arguments.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(blocks, forKey: .blocks)
        try container.encodeIfPresent(close, forKey: .close)
        try container.encodeIfPresent(submit, forKey: .submit)
        try container.encodeIfPresent(privateMetadata, forKey: .privateMetadata)
        try container.encodeIfPresent(callbackId, forKey: .callbackId)
        try container.encodeIfPresent(clearOnClose, forKey: .clearOnClose)
        try container.encodeIfPresent(notifyOnClose, forKey: .notifyOnClose)
        try container.encodeIfPresent(externalId, forKey: .externalId)
        try container.encodeIfPresent(submitDisabled, forKey: .submitDisabled)
    }
}
