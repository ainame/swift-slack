import Foundation
import SlackBlockKit
import SlackBlockKitDSL
import Testing

struct AuthProviderTests {
    @Test func `auth provider composes inside a container`() throws {
        let provider = AuthProviderBlock(value: "acme", name: "Acme", isConnected: false, fallback: [.divider(DividerBlock())])
        let container = ContainerBlock { provider }
        #expect(container.childBlocks == [.authProvider(provider)])
        let encoded = try JSONEncoder().encode(container.render())
        #expect(try JSONDecoder().decode(Block.self, from: encoded) == container.render())
    }
}
