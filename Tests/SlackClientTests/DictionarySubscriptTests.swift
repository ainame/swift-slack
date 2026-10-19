import Foundation
import SlackClient
import Testing

struct DictionarySubscriptTests {
    @Test func `map wrappers read like dictionaries`() throws {
        let json = #"{ "profile": { "fields": { "Xf123": { "value": "Engineering", "alt": "" } } } }"#
        let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))

        #expect(user.profile?.fields?["Xf123"]?.value == "Engineering")
        #expect(user.profile?.fields?["missing"] == nil)
    }
}
