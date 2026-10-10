import Foundation
import SlackClient

public struct SlashCommandsPayload: Decodable, Hashable, Sendable {
    public let command: String
    public let text: String
    public let responseUrl: URL
    public let triggerId: String
    public let userId: String
    public let userName: String
    public let channelId: String
    public let channelName: String
    public let teamId: String
    public let teamDomain: String
    public let isEnterpriseInstall: Bool
    public let enterpriseId: String?
    public let enterpriseName: String?
    public let apiAppId: String

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        text = try container.decode(String.self, forKey: .text)
        responseUrl = try container.decode(URL.self, forKey: .responseUrl)
        triggerId = try container.decode(String.self, forKey: .triggerId)
        userId = try container.decode(String.self, forKey: .userId)
        userName = try container.decode(String.self, forKey: .userName)
        channelId = try container.decode(String.self, forKey: .channelId)
        channelName = try container.decode(String.self, forKey: .channelName)
        teamDomain = try container.decode(String.self, forKey: .teamDomain)
        teamId = try container.decode(String.self, forKey: .teamId)
        enterpriseId = try container.decodeIfPresent(String.self, forKey: .enterpriseId)
        enterpriseName = try container.decodeIfPresent(String.self, forKey: .enterpriseName)
        // I found this is being boolean in string :)
        do {
            isEnterpriseInstall = try container.decode(Bool.self, forKey: .isEnterpriseInstall)
        } catch {
            let isEnterpriseInstall = try container.decodeIfPresent(String.self, forKey: .isEnterpriseInstall)
            self.isEnterpriseInstall = switch isEnterpriseInstall {
            case "true": true
            case "false": false
            default: enterpriseId != nil // If enterpriseId is found, it'd be true
            }
        }
        apiAppId = try container.decode(String.self, forKey: .apiAppId)
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case text
        case responseUrl = "response_url"
        case triggerId = "trigger_id"
        case userId = "user_id"
        case userName = "user_name"
        case channelId = "channel_id"
        case channelName = "channel_name"
        case teamDomain = "team_domain"
        case teamId = "team_id"
        case isEnterpriseInstall = "is_enterprise_install"
        case enterpriseId = "enterprise_id"
        case enterpriseName = "enterprise_name"
        case apiAppId = "api_app_id"
    }
}
