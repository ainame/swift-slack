import SlackKit

/// The three Web API calls behind a streaming message. ``ChatStream`` decides when to make them.
public protocol ChatStreamTransport: Sendable {
    /// Calls `chat.startStream` and returns the streaming message's `ts`.
    func start(chunks: [StreamChunk]) async throws -> String
    /// Calls `chat.appendStream`.
    func append(ts: String, chunks: [StreamChunk]) async throws
    /// Calls `chat.stopStream`.
    func stop(ts: String, chunks: [StreamChunk], blocks: [Block]?, sessionStatus: String?) async throws
}

/// Streams into one thread through the Slack Web API.
public struct SlackChatStreamTransport: ChatStreamTransport {
    public enum TaskDisplayMode: String, Sendable {
        /// Task updates render as task cards interleaved with the text.
        case timeline
        /// Task updates render together in a plan block.
        case plan
    }

    private let client: any APIProtocol
    private let channel: String
    private let threadTs: String
    private let recipientUserId: String?
    private let recipientTeamId: String?
    private let taskDisplayMode: TaskDisplayMode

    /// - Parameters:
    ///   - recipientUserId: The user the reply is for. Slack requires it, with `recipientTeamId`, when
    ///     streaming into a channel rather than a DM with the app.
    public init(
        client: any APIProtocol,
        channel: String,
        threadTs: String,
        recipientUserId: String? = nil,
        recipientTeamId: String? = nil,
        taskDisplayMode: TaskDisplayMode = .timeline,
    ) {
        self.client = client
        self.channel = channel
        self.threadTs = threadTs
        self.recipientUserId = recipientUserId
        self.recipientTeamId = recipientTeamId
        self.taskDisplayMode = taskDisplayMode
    }

    public func start(chunks: [StreamChunk]) async throws -> String {
        let response = try await client.chatStartStream(body: .json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            threadTs: threadTs,
            recipientUserId: recipientUserId,
            recipientTeamId: recipientTeamId,
            taskDisplayMode: taskDisplayMode.rawValue,
        ))).ok.body.json.checked("chat.startStream")
        guard let ts = response.ts else {
            throw SlackAPIError(method: "chat.startStream", code: "missing_ts")
        }
        return ts
    }

    public func append(ts: String, chunks: [StreamChunk]) async throws {
        _ = try await client.chatAppendStream(body: .json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            ts: ts,
        ))).ok.body.json.checked("chat.appendStream")
    }

    public func stop(ts: String, chunks: [StreamChunk], blocks: [Block]?, sessionStatus: String?) async throws {
        _ = try await client.chatStopStream(body: .json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            ts: ts,
            blocks: blocks,
            sessionStatus: sessionStatus,
        ))).ok.body.json.checked("chat.stopStream")
    }
}
