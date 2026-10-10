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
            "id": "V123",
            "hash": "1571318366.2468e46f",
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
        #expect(payload.view?.id == "V123")
        #expect(payload.view?.hash == "1571318366.2468e46f")
        #expect(payload.callbackId == "nag_modal")
    }

    @Test
    func `decode button action`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        {
          "type": "button",
          "action_id": "approve",
          "block_id": "request_1",
          "text": { "type": "plain_text", "text": "Approve", "emoji": true },
          "value": "1",
          "style": "primary",
          "action_ts": "1771366540.123456"
        }
        """)

        let action = try #require(payload.blockActions.first)
        #expect(action._type == "button")
        #expect(action.actionId == "approve")
        #expect(action.blockId == "request_1")
        #expect(action.actionTs == "1771366540.123456")
        #expect(action.text?.text == "Approve")
        #expect(action.value == "1")
        #expect(action.style == "primary")
        #expect(payload.containsAction("approve"))
        #expect(payload.containsAction("approve", blockId: "request_1"))
        #expect(!payload.containsAction("approve", blockId: "request_2"))
        #expect(!payload.containsAction("deny"))
    }

    @Test
    func `decode link button actions with valid and invalid URLs`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        {
          "type": "button",
          "action_id": "docs",
          "block_id": "b1",
          "text": { "type": "plain_text", "text": "Docs" },
          "url": "https://docs.slack.dev",
          "action_ts": "1.1"
        },
        {
          "type": "button",
          "action_id": "empty",
          "block_id": "b2",
          "text": { "type": "plain_text", "text": "Empty" },
          "url": "",
          "action_ts": "1.2"
        }
        """)

        let actions = payload.blockActions
        #expect(actions[0].url?.absoluteString == "https://docs.slack.dev")
        #expect(actions[1].url == nil)
        #expect(actions[1].actionId == "empty")
    }

    @Test
    func `decode option actions without element options`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        {
          "type": "checkboxes",
          "action_id": "toppings",
          "block_id": "b1",
          "selected_options": [
            { "text": { "type": "plain_text", "text": "Cheese" }, "value": "cheese" }
          ],
          "action_ts": "1.1"
        },
        {
          "type": "overflow",
          "action_id": "more",
          "block_id": "b2",
          "selected_option": { "text": { "type": "plain_text", "text": "Edit" }, "value": "edit" },
          "action_ts": "1.2"
        },
        {
          "type": "radio_buttons",
          "action_id": "size",
          "block_id": "b3",
          "selected_option": null,
          "action_ts": "1.3"
        },
        {
          "type": "multi_static_select",
          "action_id": "tags",
          "block_id": "b4",
          "selected_options": [],
          "action_ts": "1.4"
        }
        """)

        let actions = payload.blockActions
        #expect(actions.map(\._type) == ["checkboxes", "overflow", "radio_buttons", "multi_static_select"])
        #expect(actions[0].selectedOptions?.map(\.value) == ["cheese"])
        #expect(actions[1].selectedOption?.value == "edit")
        #expect(actions[2].selectedOption == nil)
        #expect(actions[3].selectedOptions == [])
    }

    @Test
    func `decode picker and select actions`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        { "type": "datepicker", "action_id": "date", "block_id": "b", "selected_date": "2026-10-04", "action_ts": "1" },
        { "type": "timepicker", "action_id": "time", "block_id": "b", "selected_time": "09:30", "action_ts": "1" },
        { "type": "datetimepicker", "action_id": "datetime", "block_id": "b", "selected_date_time": 1791100800, "action_ts": "1" },
        { "type": "users_select", "action_id": "user", "block_id": "b", "selected_user": "U123", "action_ts": "1" },
        { "type": "multi_channels_select", "action_id": "channels", "block_id": "b", "selected_channels": ["C1", "C2"], "action_ts": "1" }
        """)

        let actions = payload.blockActions
        #expect(actions[0].selectedDate == "2026-10-04")
        #expect(actions[1].selectedTime == "09:30")
        #expect(actions[2].selectedDateTime == 1_791_100_800)
        #expect(actions[3].selectedUser == "U123")
        #expect(actions[4].selectedChannels == ["C1", "C2"])
    }

    @Test
    func `decode dispatch input and unknown element actions`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        {
          "type": "plain_text_input",
          "action_id": "title",
          "block_id": "b1",
          "value": "Hello",
          "action_ts": "1.1"
        },
        {
          "type": "rich_text_input",
          "action_id": "notes",
          "block_id": "b2",
          "rich_text_value": {
            "type": "rich_text",
            "elements": [
              { "type": "rich_text_section", "elements": [{ "type": "text", "text": "Hi" }] }
            ]
          },
          "action_ts": "1.2"
        },
        {
          "type": "rich_text_input",
          "action_id": "notes",
          "block_id": "b3",
          "rich_text_value": {
            "type": "rich_text",
            "elements": [{ "type": "rich_text_future_element" }]
          },
          "action_ts": "1.3"
        },
        {
          "type": "future_element",
          "action_id": "future",
          "block_id": "b4",
          "some_new_field": { "nested": true },
          "action_ts": "1.4"
        }
        """)

        let actions = payload.blockActions
        #expect(actions[0]._type == "plain_text_input")
        #expect(actions[0].value == "Hello")
        #expect(actions[1].richTextValue?.elements.count == 1)
        // Unmodeled rich text elements are preserved as .unknown rather than dropping the value.
        guard case .unknown("rich_text_future_element", _)? = actions[2].richTextValue?.elements.first else {
            Issue.record("Expected an unknown rich text element")
            return
        }
        #expect(actions[3]._type == "future_element")
        #expect(actions[3].actionId == "future")
    }

    @Test
    @available(*, deprecated)
    func `deprecated actions skips elements that do not decode as Block Kit elements`() throws {
        let payload = try decodeMessageBlockActions(actions: """
        {
          "type": "checkboxes",
          "action_id": "toppings",
          "block_id": "b1",
          "selected_options": [],
          "action_ts": "1.1"
        },
        {
          "type": "button",
          "action_id": "approve",
          "block_id": "b2",
          "text": { "type": "plain_text", "text": "Approve" },
          "action_ts": "1.2"
        }
        """)

        #expect(payload.blockActions.map(\.actionId) == ["toppings", "approve"])
        let elements = try #require(payload.actions)
        #expect(elements.count == 1)
        guard case let .button(button) = elements.first else {
            Issue.record("Expected the button element")
            return
        }
        #expect(button.actionId == "approve")
    }
}

private func decodeMessageBlockActions(actions: String) throws -> BlockActionsPayload {
    let json = """
    {
      "type": "block_actions",
      "user": { "id": "U03TQQSQH25" },
      "team": { "id": "T03T5HH7T9U" },
      "container": {
        "type": "message",
        "message_ts": "1771366531.702529",
        "channel_id": "C0AFCSU2AKD",
        "is_ephemeral": false
      },
      "actions": [\(actions)]
    }
    """
    return try JSONDecoder().decode(BlockActionsPayload.self, from: #require(json.data(using: .utf8)))
}
