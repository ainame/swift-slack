import Foundation
import SlackBlockKit
import Testing

struct AuthProviderBlockTests {
    // Verbatim payloads from upstream java-slack-sdk BlockKitTest at 383dd5f35.
    @Test(arguments: upstreamPayloads)
    func `upstream auth provider view round trip`(json: String) throws {
        let data = Data(json.utf8)
        let view = try JSONDecoder().decode(View.self, from: data)
        let encoded = try JSONEncoder().encode(view)
        #expect(try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(try JSONDecoder().decode(View.self, from: encoded) == view)
    }

    @Test func `auth provider exposes all upstream fields`() throws {
        let view = try JSONDecoder().decode(HomeTabView.self, from: Data(Self.upstreamPayloads[0].utf8))
        guard case let .authProvider(provider) = try #require(view.blocks.first) else {
            Issue.record("Expected an auth provider block")
            return
        }
        #expect(provider.type == "auth_provider")
        #expect(provider.blockId == "auth1")
        #expect(provider.value == "acme")
        #expect(provider.name.text == "Acme")
        #expect(provider.isConnected)
        #expect(provider.description?.text == "Search Acme docs")
        #expect(provider.iconUrl?.absoluteString == "https://acme.example.com/icon.png")
        #expect(provider.authUrl?.absoluteString == "https://acme.example.com/oauth")
        #expect(provider.disconnectUrl?.absoluteString == "https://acme.example.com/disconnect")
        #expect(provider.connectedIdentity?.text == "jane@acme.example.com")
        #expect(provider.connectedContext?.text == "Acme Corp")
        #expect(provider.accessory?.actionId == "acme_menu")
        #expect(provider.accessory?.options.map(\.value) == ["switch", "disconnect"])
        #expect(provider.fallback == [.section(SectionBlock(text: TextObject(type: .mrkdwn, text: "Connected to Acme")))])
    }

    private static let upstreamPayloads = [
        #"""
        {"type":"home","blocks":[
          {
            "type": "auth_provider",
            "block_id": "auth1",
            "value": "acme",
            "name": {"type": "plain_text", "text": "Acme"},
            "is_connected": true,
            "description": {"type": "plain_text", "text": "Search Acme docs"},
            "icon_url": "https://acme.example.com/icon.png",
            "auth_url": "https://acme.example.com/oauth",
            "disconnect_url": "https://acme.example.com/disconnect",
            "connected_identity": {"type": "plain_text", "text": "jane@acme.example.com"},
            "connected_context": {"type": "plain_text", "text": "Acme Corp"},
            "accessory": {
              "type": "overflow",
              "action_id": "acme_menu",
              "options": [
                {"text": {"type": "plain_text", "text": "Switch accounts"}, "value": "switch"},
                {"text": {"type": "plain_text", "text": "Disconnect"}, "value": "disconnect"}
              ]
            },
            "fallback": [
              {"type": "section", "text": {"type": "mrkdwn", "text": "Connected to Acme"}}
            ]
          }
        ]}
        """#,
        #"""
        {"type":"home","blocks":[
          {
            "type": "auth_provider",
            "value": "acme",
            "name": {"type": "plain_text", "text": "Acme"},
            "is_connected": false
          }
        ]}
        """#,
    ]
}
