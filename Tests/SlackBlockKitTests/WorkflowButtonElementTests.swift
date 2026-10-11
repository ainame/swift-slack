import Foundation
@testable import SlackBlockKit
import Testing

private let buttonJSON = #"{"type":"workflow_button","text":{"type":"plain_text","text":"Run Workflow"},"action_id":"workflowbutton123","style":"primary","accessibility_label":"Run it","workflow":{"trigger":{"url":"https://slack.com/shortcuts/Ft0123ABC456/xyz","customizable_input_parameters":[{"name":"input_parameter_a","value":"Value for input param A"},{"name":"input_parameter_b","value":"Value for input param B"}]}}}"#

private func jsonObject(_ json: String) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
}

@Test
func `Workflow button as section accessory round-trips`() throws {
    let json = #"{"type":"section","text":{"type":"mrkdwn","text":"A message *with some bold text*."},"accessory":\#(buttonJSON)}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .section(section) = block, case let .workflowButton(button) = section.accessory else {
        Issue.record("Expected section with workflow button accessory, got \(block)")
        return
    }
    #expect(button.actionId == "workflowbutton123")
    #expect(button.style == .primary)
    #expect(button.workflow.trigger.customizableInputParameters?.count == 2)

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try jsonObject(json)))
}

@Test
func `Workflow button in actions block round-trips`() throws {
    let json = #"{"type":"actions","elements":[\#(buttonJSON)]}"#
    let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))

    guard case let .actions(actions) = block, case .workflowButton = actions.elements.first else {
        Issue.record("Expected actions with workflow button, got \(block)")
        return
    }

    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    #expect(encoded == (try jsonObject(json)))
}
