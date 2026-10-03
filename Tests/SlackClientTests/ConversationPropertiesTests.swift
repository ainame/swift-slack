import Foundation
@testable import SlackClient
import SlackModels
import Testing

struct ConversationPropertiesTests {
    @Test
    func `conversations info preserves record code and agent properties`() throws {
        #if WebAPI_Conversations
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../vendor/java-slack-sdk/json-logs/samples/api/conversations.info.json")
        let data = try Data(contentsOf: fixture)
        let response = try JSONDecoder().decode(Components.Schemas.ConversationsInfoResponse.self, from: data)
        let channel = try #require(response.channel)
        let properties = try #require(channel.properties)
        #expect(channel.isOpen == false)
        #expect(properties.recordChannel?.recordId == "")
        #expect(properties.recordChannel?.recordLabelPlural == "")
        #expect(properties.codeChannel?.contextBarItems?.first?.url == "https://www.example.com/")
        #expect(properties.codeChannel?.contextBarItems?.first?.botUserId == "U00000000")
        #expect(properties.agentSession?.status == "")
        #expect(properties.agentSession?.agentBotUserIds == [""])
        #expect(properties.agentSession?.encodedAgentBotUserIds == ["U00000000"])
        #expect(properties.agentSession?.originLink?.channelId == "C00000000")
        #expect(properties.agentSession?.originLink?.ts == "0000000000.000000")

        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let originalChannel = try #require(original["channel"] as? [String: Any])
        let originalProperties = try #require(originalChannel["properties"] as? [String: Any])
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(properties)) as? [String: Any])
        for key in ["record_channel", "code_channel", "agent_session"] {
            let expected = try #require(originalProperties[key] as? NSDictionary)
            let actual = try #require(encoded[key] as? NSDictionary)
            #expect(actual == expected)
        }
        #endif
    }

    @Test
    func `older conversations omit the new properties`() throws {
        let properties = try JSONDecoder().decode(Properties.self, from: Data("{\"use_case\":\"project\"}".utf8))
        #expect(properties.useCase == "project")
        #expect(properties.recordChannel == nil)
        #expect(properties.codeChannel == nil)
        #expect(properties.agentSession == nil)
    }
}
