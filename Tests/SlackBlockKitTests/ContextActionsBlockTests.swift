import Foundation
@testable import SlackBlockKit
import Testing

@Test
func `Context actions block with feedback buttons decodes and round-trips`() throws {
    let json = #"{"type":"context_actions","elements":[{"type":"feedback_buttons","action_id":"feedback_buttons_1","positive_button":{"text":{"type":"plain_text","text":"Good"},"value":"positive_feedback","accessibility_label":"Mark this response as good"},"negative_button":{"text":{"type":"plain_text","text":"Bad"},"value":"negative_feedback"}}],"block_id":"b1"}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .contextActions(contextActions) = block,
          case let .feedbackButtons(feedback) = contextActions.elements.first
    else {
        Issue.record("Expected .contextActions with feedback buttons, got \(block)")
        return
    }
    #expect(feedback.actionId == "feedback_buttons_1")
    #expect(feedback.positiveButton.value == "positive_feedback")
    #expect(feedback.positiveButton.accessibilityLabel == "Mark this response as good")
    #expect(feedback.negativeButton.accessibilityLabel == nil)

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)))
}

@Test
func `Context actions block with icon button decodes and round-trips`() throws {
    let json = #"{"type":"context_actions","elements":[{"type":"icon_button","icon":"trash","text":{"type":"plain_text","text":"Delete"},"action_id":"delete_button","value":"delete_item","accessibility_label":"Delete it","visible_to_user_ids":["U123","U456"]},{"type":"future_element"}]}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .contextActions(contextActions) = block,
          case let .iconButton(button) = contextActions.elements.first
    else {
        Issue.record("Expected .contextActions with icon button, got \(block)")
        return
    }
    #expect(button.icon == "trash")
    #expect(button.visibleToUserIds == ["U123", "U456"])
    guard case .unknown("future_element", _) = contextActions.elements[1] else {
        Issue.record("Expected unknown element")
        return
    }

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)))
}
