import Foundation
@testable import SlackBlockKit
import Testing

struct ConversationFilterObjectTests {
    @Test func `uses Slack's snake_case keys`() throws {
        let json = #"{ "include": ["public", "im"], "exclude_external_shared_channels": true, "exclude_bot_users": true }"#

        let filter = try JSONDecoder().decode(ConversationFilterObject.self, from: Data(json.utf8))
        #expect(filter.include == [.public, .im])
        #expect(filter.excludeExternalSharedChannels == true)
        #expect(filter.excludeBotUsers == true)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(filter)) as? [String: Any]
        #expect(encoded?["exclude_external_shared_channels"] as? Bool == true)
        #expect(encoded?["exclude_bot_users"] as? Bool == true)
    }
}
