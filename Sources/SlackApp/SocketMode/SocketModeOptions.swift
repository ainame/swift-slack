public struct SocketModeOptions: OptionSet, RawRepresentable, Sendable {
    /// If enabled, ``SlackApp`` will automatically re-connect when the current connection ends.
    public static let autoReconnectWhenDisconnected = SocketModeOptions(rawValue: 1 << 0)

    /// If enabled, ``SlackApp`` will not propagate app-level errors to the caller and will continue
    /// waiting for the next message automatically.
    ///
    /// Any errors occured at lower-layer like following categories are not impacted with this and un-handled.
    ///
    /// * WebSocket library (WSClient)
    /// * Networking failure for WebSocket
    ///
    /// Messages that fail to decode are always logged and skipped, regardless of this option. As in HTTP mode,
    /// Events API envelopes are acknowledged, and interactive requests and slash commands are not, so Slack
    /// shows the user an error. Please report them to get them fixed.
    public static let recoverFromAppError = SocketModeOptions(rawValue: 1 << 1)

    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
