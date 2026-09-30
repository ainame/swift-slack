import Foundation

/// The arguments that `api.test` echoes back in its response.
///
/// `error` is the only documented argument; `foo` is the parameter used in Slack's echo
/// example. Mirrors `ApiTestResponse.Args` in java-slack-sdk.
public struct APITestArgs: Codable, Hashable, Sendable {
    public var error: Swift.String?
    public var foo: Swift.String?

    public init(
        error: Swift.String? = nil,
        foo: Swift.String? = nil,
    ) {
        self.error = error
        self.foo = foo
    }
}
