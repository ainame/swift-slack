import Foundation
@testable import SlackBlockKit
import Testing

struct MultiStaticSelectElementTests {
    @Test func `decodes option groups instead of options`() throws {
        let json = """
        {
            "type": "multi_static_select",
            "action_id": "pick",
            "option_groups": [
                {
                    "label": { "type": "plain_text", "text": "Group" },
                    "options": [{ "text": { "type": "plain_text", "text": "A" }, "value": "a" }]
                }
            ]
        }
        """

        let element = try JSONDecoder().decode(MultiStaticSelectElement.self, from: Data(json.utf8))

        #expect(element.options == nil)
        #expect(element.optionGroups?.first?.options.first?.value == "a")
    }
}
