import Foundation
import SlackClient
import Testing

struct CodeChannelReadbackTests {
    #if WebAPI_Conversations
    @Test func `documented Code channel properties survive decoding and reencoding`() throws {
        let data = try fixture("ConversationsInfoResponse")
        let response = try JSONDecoder().decode(Components.Schemas.ConversationsInfoResponse.self, from: data)
        let codeChannel = try #require(response.channel?.properties?.codeChannel)
        #expect(codeChannel.summaryMessage?.messageTs == "123.456")
        #expect(codeChannel.summaryMessage?.threadTs == "123.000")
        #expect(codeChannel.contextBarItems?.first?.itemType == "action")
        let views = try #require(codeChannel.agentSessionViews)
        #expect(views.count == 2)
        #expect(views[0]._type == "diff")
        #expect(views[0].name == "Changes")
        #expect(views[0].viewKey == nil)
        #expect(views[0].dateAdded == 1_717_171_717)
        #expect(views[0].contentVersion == 3)
        #expect(views[1].viewKey == "report.html")
        try expectRoundTrip(response, data)
    }

    @Test func `older Code channel responses omit supplemented properties`() throws {
        let data = Data(#"{"ok":true,"channel":{"properties":{"code_channel":{}}}}"#.utf8)
        let response = try JSONDecoder().decode(Components.Schemas.ConversationsInfoResponse.self, from: data)
        let codeChannel = try #require(response.channel?.properties?.codeChannel)
        #expect(codeChannel.summaryMessage == nil)
        #expect(codeChannel.agentSessionViews == nil)
        try expectRoundTrip(response, data)
    }
    #endif

    @Test func `Code channel manifest feature survives decoding and reencoding`() throws {
        let data = try fixture("AppManifest")
        let manifest = try JSONDecoder().decode(AppManifest.self, from: data)
        #expect(manifest.features?.codeChannels?.enabled == true)
        #expect(manifest.features?.codeChannels?.slashCommandUrl == "https://example.com/slack/code-channel-commands")
        try expectRoundTrip(manifest, data)
        let constructed = AppManifest(features: .init(codeChannels: .init(
            enabled: true, slashCommandUrl: "https://example.com/slack/code-channel-commands",
        )))
        try expectRoundTrip(constructed, data)
    }

    @Test func `Socket Mode manifest can omit the command URL`() throws {
        let data = Data(#"{"features":{"code_channels":{"enabled":true}}}"#.utf8)
        let manifest = try JSONDecoder().decode(AppManifest.self, from: data)
        #expect(manifest.features?.codeChannels?.enabled == true)
        #expect(manifest.features?.codeChannels?.slashCommandUrl == nil)
        try expectRoundTrip(manifest, data)
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("scripts/slack_code_fixtures/\(name).json"))
    }

    private func expectRoundTrip(_ value: some Encodable, _ data: Data) throws {
        let expected = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let actual = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
        #expect(actual == expected)
    }
}
