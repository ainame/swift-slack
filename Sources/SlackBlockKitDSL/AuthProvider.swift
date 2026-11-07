import SlackBlockKit

extension AuthProviderBlock: BlockComponent {
    public func render() -> Block {
        .authProvider(self)
    }
}
