import Foundation
import SlackModels

public protocol InteractivePayloadProtocol: Decodable, Hashable, Sendable {
    var user: SlackModels.User { get }
    var callbackId: String? { get }
}

public enum InteractivePayload: Decodable, Hashable, Sendable {
    case shortcut(GlobalShortcutPayload)
    case messageAction(MessageShortcutPayload)
    case blockActions(BlockActionsPayload)
    case viewSubmission(ViewSubmissionPayload)
    case viewClosed(ViewClosedPayload)
    case blockSuggestion(BlockSuggestionPayload)
    case unsupported(String)
}

extension InteractivePayload {
    public var _type: String {
        switch self {
        case let .shortcut(payload): payload._type
        case let .messageAction(payload): payload._type
        case let .blockActions(payload): payload._type
        case let .viewClosed(payload): payload._type
        case let .viewSubmission(payload): payload._type
        case let .blockSuggestion(payload): payload._type
        case let .unsupported(t): t
        }
    }
}
