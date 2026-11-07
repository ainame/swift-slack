import Foundation

/// Outer structure is a common wrapper to accomodate specific event's inner event payload on `event` field
/// https://docs.slack.dev/apis/events-api/
///
/// The deprecated `token`, `authed_users` and `authed_teams` fields are not decoded; use `authorizations` instead.
public struct EventsApiEnvelope<Event: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    /// An installation of the app that the event is visible to.
    public struct Authorization: Decodable, Hashable, Sendable {
        public let enterpriseId: String?
        public let teamId: String?
        public let userId: String?
        public let isBot: Bool?
        public let isEnterpriseInstall: Bool?

        private enum CodingKeys: String, CodingKey {
            case enterpriseId = "enterprise_id"
            case teamId = "team_id"
            case userId = "user_id"
            case isBot = "is_bot"
            case isEnterpriseInstall = "is_enterprise_install"
        }
    }

    public let teamId: String
    /// The Enterprise Grid organization, for org-level installs and workspaces in an organization.
    public let enterpriseId: String?
    public let contextTeamId: String?
    public let contextEnterpriseId: String?
    public let apiAppId: String
    public let event: Event
    public let type: String
    public let eventId: String
    public let eventTime: Int
    /// An identifier for the event's context, used by `apps.event.authorizations.list`.
    public let eventContext: String?
    /// One installation of the app that the event is visible to; list them all with `apps.event.authorizations.list`.
    public let authorizations: [Authorization]?
    public let isExtSharedChannel: Bool?

    private enum CodingKeys: String, CodingKey {
        case teamId = "team_id"
        case enterpriseId = "enterprise_id"
        case contextTeamId = "context_team_id"
        case contextEnterpriseId = "context_enterprise_id"
        case apiAppId = "api_app_id"
        case event
        case type
        case eventId = "event_id"
        case eventTime = "event_time"
        case eventContext = "event_context"
        case authorizations
        case isExtSharedChannel = "is_ext_shared_channel"
    }
}
