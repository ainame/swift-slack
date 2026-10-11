import SlackKit

/// The `ok`, `error`, and `warning` fields every Web API response carries.
///
/// swift-slack decodes `"ok": false` responses without throwing, so callers check them with ``checked(_:)``.
public protocol SlackResponse {
    var ok: Bool { get }
    var error: String? { get }
    var warning: String? { get }
}

public struct SlackAPIError: Error, CustomStringConvertible {
    public let method: String
    public let code: String

    public init(method: String, code: String) {
        self.method = method
        self.code = code
    }

    public var description: String {
        "\(method) failed: \(code)"
    }
}

extension SlackResponse {
    /// Returns the response, or throws ``SlackAPIError`` when Slack answered `"ok": false`.
    public func checked(_ method: String) throws -> Self {
        guard ok else {
            throw SlackAPIError(method: method, code: error ?? "unknown_error")
        }
        return self
    }
}

extension Components.Schemas.ChatStartStreamResponse: SlackResponse {}
extension Components.Schemas.ChatAppendStreamResponse: SlackResponse {}
extension Components.Schemas.ChatStopStreamResponse: SlackResponse {}
extension Components.Schemas.ChatPostEphemeralResponse: SlackResponse {}
extension Components.Schemas.AgentsSessionsSetStatusResponse: SlackResponse {}
extension Components.Schemas.AssistantThreadsSetSuggestedPromptsResponse: SlackResponse {}
