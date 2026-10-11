import Foundation
import OpenAPIRuntime
import SlackBlockKit
import SlackClient

/// https://docs.slack.dev/reference/interaction-payloads/view-interactions-payload#view_closed
public struct ViewClosedPayload: InteractivePayloadProtocol, Decodable, Sendable {
    /// "view_closed"
    public let _type: String
    public let enterprise: Enterprise?
    public let team: Team
    public let user: User
    public let apiAppId: String?
    public let view: View
    public let isEnterpriseInstall: Bool?
    public let isCleared: Bool
    /// Function-only metadata
    public let functionData: FunctionData?
    /// Function-only interactivity context
    public let interactivity: Interactivity?
    /// Function-only just-in-time token
    public let botAccessToken: String?

    private enum CodingKeys: String, CodingKey {
        case _type = "type"
        case enterprise
        case team
        case user
        case apiAppId = "api_app_id"
        case view
        case isEnterpriseInstall = "is_enterprise_install"
        case isCleared = "is_cleared"
        case functionData = "function_data"
        case interactivity
        case botAccessToken = "bot_access_token"
    }
}

extension ViewClosedPayload {
    public var callbackId: String? {
        view.callbackId
    }
}

extension ViewClosedPayload {
    public struct FunctionData: Decodable, Hashable, Sendable {
        public let executionId: String?
        public let function: Function?
        public let inputs: OpenAPIObjectContainer?

        private enum CodingKeys: String, CodingKey {
            case executionId = "execution_id"
            case function
            case inputs
        }

        public struct Function: Decodable, Hashable, Sendable {
            public let callbackId: String?

            private enum CodingKeys: String, CodingKey {
                case callbackId = "callback_id"
            }
        }
    }

    public struct Interactivity: Decodable, Hashable, Sendable {
        public let interactivityPointer: String?
        public let interactor: Interactor?

        private enum CodingKeys: String, CodingKey {
            case interactivityPointer = "interactivity_pointer"
            case interactor
        }

        public struct Interactor: Decodable, Hashable, Sendable {
            public let id: String?
            public let secret: String?
        }
    }
}
