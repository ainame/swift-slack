import Foundation
import SlackBlockKit
import Testing

struct PlanAndPromptTests {
    @Test func `plan tasks round trip without a block type`() throws {
        let data = Data(#"""
        {"type":"plan","title":"Thinking completed","block_id":"plan_1","tasks":[
          {"task_id":"call_001","title":"Fetched user profile information","status":"in_progress",
           "details":{"type":"rich_text","block_id":"viMWO","elements":[
             {"type":"rich_text_section","elements":[{"type":"text","text":"Searched database..."}]}
           ]}},
          {"task_id":"call_002","title":"Checked user permissions","status":"in_progress"}
        ]}
        """#.utf8)

        let block = try JSONDecoder().decode(Block.self, from: data)
        guard case let .plan(plan) = block else {
            Issue.record("Expected a plan block")
            return
        }
        #expect(plan.tasks.map(\.taskId) == ["call_001", "call_002"])
        #expect(plan.tasks.first?.details?.blockId == "viMWO")
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary ==
            JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func `button preserves prompt and visibility fields`() throws {
        let data = Data(#"""
        {"type":"button","text":{"type":"plain_text","text":"Summarize with Slackbot"},
         "action_id":"summarize_incident","agent_prompt":"Summarize this incident and suggest next steps.",
         "agent_prompt_display":"Summarize this incident","visible_to_user_ids":["U123456"]}
        """#.utf8)

        let button = try JSONDecoder().decode(ButtonElement.self, from: data)
        #expect(button.agentPrompt == "Summarize this incident and suggest next steps.")
        #expect(button.agentPromptDisplay == "Summarize this incident")
        #expect(button.visibleToUserIds == ["U123456"])
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(button)) as? NSDictionary ==
            JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
