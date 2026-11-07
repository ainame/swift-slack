#if Events
import Foundation
@testable import SlackApp
import Testing

struct EventsApiEnvelopeTests {
    @Test
    func `org-level install fields decode`() throws {
        let json = """
        {
          "token": "legacy",
          "team_id": "T123",
          "enterprise_id": "E123",
          "context_team_id": "T456",
          "context_enterprise_id": "E456",
          "api_app_id": "A123",
          "event": {
            "type": "app_mention",
            "channel": "C123",
            "user": "U123",
            "text": "hi",
            "ts": "1783536983.783769",
            "event_ts": "1783536983.783769"
          },
          "type": "event_callback",
          "event_id": "Ev123",
          "event_time": 1783536983,
          "event_context": "4-abc",
          "authorizations": [
            {
              "enterprise_id": "E123",
              "team_id": null,
              "user_id": "U999",
              "is_bot": true,
              "is_enterprise_install": true
            }
          ],
          "is_ext_shared_channel": true
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(EventsApiEnvelope<Event>.self, from: json)

        #expect(envelope.enterpriseId == "E123")
        #expect(envelope.contextTeamId == "T456")
        #expect(envelope.contextEnterpriseId == "E456")
        #expect(envelope.eventContext == "4-abc")
        #expect(envelope.isExtSharedChannel == true)
        let authorization = try #require(envelope.authorizations?.first)
        #expect(authorization.enterpriseId == "E123")
        #expect(authorization.teamId == nil)
        #expect(authorization.userId == "U999")
        #expect(authorization.isBot == true)
        #expect(authorization.isEnterpriseInstall == true)
        guard case let .appMention(event) = envelope.event else {
            Issue.record("Expected .appMention, got \(envelope.event)")
            return
        }
        #expect(event.text == "hi")
    }

    @Test
    func `optional fields may be absent`() throws {
        let json = """
        {
          "team_id": "T123",
          "api_app_id": "A123",
          "event": {"type": "app_mention", "channel": "C123", "user": "U123", "text": "hi", "ts": "1", "event_ts": "1"},
          "type": "event_callback",
          "event_id": "Ev123",
          "event_time": 123
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(EventsApiEnvelope<Event>.self, from: json)

        #expect(envelope.teamId == "T123")
        #expect(envelope.enterpriseId == nil)
        #expect(envelope.contextTeamId == nil)
        #expect(envelope.authorizations == nil)
        #expect(envelope.isExtSharedChannel == nil)
    }
}
#endif
