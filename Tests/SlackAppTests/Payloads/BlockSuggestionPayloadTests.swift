import Foundation
@testable import SlackApp
import Testing

struct BlockSuggestionPayloadTests {
    @Test func `decode block suggestion from a modal`() throws {
        // The modal example from Slack's block_suggestion payload reference.
        let json = """
        {
          "type": "block_suggestion",
          "team": { "id": "ABC123DEF45", "domain": "workspace" },
          "enterprise": null,
          "user": { "id": "EXAMPLE1234", "name": "sallyslack", "team_id": "ABC123DEF45" },
          "view": {
            "id": "DEFGHIJ89101",
            "team_id": "ABC123DEF45",
            "app_id": "APPID6789101",
            "app_installed_team_id": "ABC123DEF45",
            "bot_id": "BOTSRCOOL12",
            "title": { "type": "plain_text", "text": "Deny Request", "emoji": true },
            "type": "modal",
            "blocks": [],
            "close": null,
            "submit": { "type": "plain_text", "text": "Next", "emoji": true },
            "state": { "values": {} },
            "hash": "1695235327.610lSjjQ",
            "private_metadata": "{\\"messageTS\\":\\"1695235212.424669\\"}",
            "callback_id": "deny_modal_main",
            "root_view_id": "DEFGHIJ89101",
            "previous_view_id": null,
            "clear_on_close": false,
            "notify_on_close": true,
            "external_id": ""
          },
          "container": { "type": "view", "view_id": "DEFGHIJ89101" },
          "api_app_id": "APPID6789101",
          "action_id": "ext_select_input",
          "block_id": "ext_select_block",
          "value": "tech",
          "function_data": {
            "execution_id": "EXECUTEF9101",
            "function": { "callback_id": "review_approval" },
            "inputs": { "details": "test", "subject": "test" }
          },
          "bot_access_token": "xwfp-test"
        }
        """

        let envelope = try JSONDecoder().decode(InteractiveEnvelope.self, from: Data(json.utf8))
        guard case let .blockSuggestion(payload) = envelope.body else {
            Issue.record("Expected a block_suggestion payload, got \(envelope.body._type)")
            return
        }

        #expect(payload._type == "block_suggestion")
        #expect(payload.user.id == "EXAMPLE1234")
        #expect(payload.team.id == "ABC123DEF45")
        #expect(payload.apiAppId == "APPID6789101")
        #expect(payload.actionId == "ext_select_input")
        #expect(payload.blockId == "ext_select_block")
        #expect(payload.value == "tech")
        #expect(payload.callbackId == "deny_modal_main")
        #expect(payload.functionData?.function?.callbackId == "review_approval")
        #expect(payload.botAccessToken == "xwfp-test")
    }

    @Test func `decode block suggestion from a message in an Enterprise org`() throws {
        // The message example from Slack's block_suggestion payload reference.
        let json = """
        {
          "type": "block_suggestion",
          "user": { "id": "ABCDE6789", "username": "harry-potter", "name": "harry-potter", "team_id": "ENT4567" },
          "container": {
            "type": "message",
            "message_ts": "1628851405.000300",
            "channel_id": "CHAN56789",
            "is_ephemeral": false
          },
          "api_app_id": "APP876543",
          "token": "XAg1RqiO8jaSczkIQpxq7Z4o",
          "action_id": "location_select-action",
          "block_id": "bK6",
          "value": "test",
          "team": {
            "id": "ENT4567",
            "domain": "my-workspace",
            "enterprise_id": "ENT123789",
            "enterprise_name": "my-enterprise"
          },
          "enterprise": { "id": "ENT123789", "name": "my-enterprise" },
          "is_enterprise_install": false,
          "channel": { "id": "CHAN56789", "name": "channel-team-01" },
          "message": {
            "bot_id": "B0T123456",
            "type": "message",
            "text": "Text+here+for+notifications",
            "user": "ABCDE6789",
            "ts": "1628851405.000300",
            "blocks": [
              {
                "type": "input",
                "block_id": "bK6",
                "label": { "type": "plain_text", "text": "Select+Location", "emoji": true },
                "optional": false,
                "dispatch_action": false,
                "element": {
                  "type": "external_select",
                  "action_id": "location_select-action",
                  "placeholder": { "type": "plain_text", "text": "Select+location", "emoji": true }
                }
              }
            ],
            "team": "ENT4567"
          }
        }
        """

        let envelope = try JSONDecoder().decode(InteractiveEnvelope.self, from: Data(json.utf8))
        guard case let .blockSuggestion(payload) = envelope.body else {
            Issue.record("Expected a block_suggestion payload, got \(envelope.body._type)")
            return
        }

        #expect(payload.actionId == "location_select-action")
        #expect(payload.blockId == "bK6")
        #expect(payload.value == "test")
        #expect(payload.enterprise?.id == "ENT123789")
        #expect(payload.isEnterpriseInstall == false)
        #expect(payload.channel?.id == "CHAN56789")
        #expect(payload.message?.ts == "1628851405.000300")
        #expect(payload.view == nil)
        #expect(payload.callbackId == nil)
    }
}
