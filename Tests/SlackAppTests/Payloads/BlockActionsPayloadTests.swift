import Foundation
@testable import SlackApp
import Testing

struct BlockActionsPayloadTests {
    @Test
    func `decode message container block actions without view`() throws {
        let json = """
        {
          "type": "block_actions",
          "token": "legacy-token",
          "hash": "1571318366.2468e46f",
          "user": {
            "id": "U03TQQSQH25"
          },
          "team": {
            "id": "T03T5HH7T9U"
          },
          "container": {
            "type": "message",
            "message_ts": "1771366531.702529",
            "channel_id": "C0AFCSU2AKD",
            "is_ephemeral": false
          },
          "response_url": "https://hooks.slack.com/actions/T03T5HH7T9U/123/abc"
        }
        """

        let payload = try JSONDecoder().decode(BlockActionsPayload.self, from: #require(json.data(using: .utf8)))

        #expect(payload._type == "block_actions")
        #expect(payload.container._type == "message")
        #expect(payload.view == nil)
        #expect(payload.callbackId == nil)
        #expect(payload.hash == "1571318366.2468e46f")
        #expect(payload.responseUrl?.absoluteString == "https://hooks.slack.com/actions/T03T5HH7T9U/123/abc")
    }

    @Test
    func `decode view container block actions with view`() throws {
        let json = """
        {
          "type": "block_actions",
          "user": {
            "id": "U03TQQSQH25"
          },
          "team": {
            "id": "T03T5HH7T9U"
          },
          "container": {
            "type": "view",
            "view_id": "V123"
          },
          "view": {
            "type": "modal",
            "callback_id": "nag_modal",
            "title": {
              "type": "plain_text",
              "text": "Test"
            },
            "blocks": []
          }
        }
        """

        let payload = try JSONDecoder().decode(BlockActionsPayload.self, from: #require(json.data(using: .utf8)))

        #expect(payload.container._type == "view")
        #expect(payload.container.viewId == "V123")
        #expect(payload.view != nil)
        #expect(payload.callbackId == "nag_modal")
    }

    @Test
    func `decode action identifiers from actions`() throws {
        let json = """
        {
          "type": "block_actions",
          "user": {
            "id": "U03TQQSQH25"
          },
          "team": {
            "id": "T03T5HH7T9U"
          },
          "container": {
            "type": "message",
            "message_ts": "1771366531.702529",
            "channel_id": "C0AFCSU2AKD",
            "is_ephemeral": false
          },
          "actions": [
            {
              "type": "button",
              "action_id": "approve",
              "block_id": "request_1",
              "text": {
                "type": "plain_text",
                "text": "Approve"
              },
              "value": "1",
              "action_ts": "1771366540.123456"
            }
          ]
        }
        """

        let payload = try JSONDecoder().decode(BlockActionsPayload.self, from: #require(json.data(using: .utf8)))

        #expect(payload.actions?.count == 1)
        #expect(payload.actionIdentifiers == [.init(actionId: "approve", blockId: "request_1")])
        #expect(payload.containsAction("approve"))
        #expect(payload.containsAction("approve", blockId: "request_1"))
        #expect(!payload.containsAction("approve", blockId: "request_2"))
        #expect(!payload.containsAction("deny"))
    }
}
