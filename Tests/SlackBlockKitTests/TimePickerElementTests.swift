import Foundation
@testable import SlackBlockKit
import Testing

struct TimePickerElementTests {
    @Test func `round trips the time zone`() throws {
        let json = #"{ "type": "timepicker", "action_id": "time", "initial_time": "09:30", "timezone": "America/Chicago" }"#

        let element = try JSONDecoder().decode(TimePickerElement.self, from: Data(json.utf8))
        #expect(element.timezone == "America/Chicago")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(element)) as? [String: Any]
        #expect(encoded?["timezone"] as? String == "America/Chicago")
    }
}
