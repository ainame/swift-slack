import OpenAPIRuntime
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
///
/// A call that Slack rate limits (HTTP 429) is retried after its `Retry-After` delay, up to three attempts.
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
        let body = try Operations.ChatStartStream.Input.Body.json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            threadTs: threadTs,
            recipientUserId: recipientUserId,
            recipientTeamId: recipientTeamId,
            taskDisplayMode: taskDisplayMode.rawValue,
        ))
        let response = try await retryingRateLimits {
            try await client.chatStartStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 {
                payload
            } else {
                nil
            }
        }.ok.body.json.checked("chat.startStream")
        guard let ts = response.ts else {
            throw SlackAPIError(method: "chat.startStream", code: "missing_ts")
        }
        return ts
    }

    public func append(ts: String, chunks: [StreamChunk]) async throws {
        let body = try Operations.ChatAppendStream.Input.Body.json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            ts: ts,
        ))
        _ = try await retryingRateLimits {
            try await client.chatAppendStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 {
                payload
            } else {
                nil
            }
        }.ok.body.json.checked("chat.appendStream")
    }

    public func stop(ts: String, chunks: [StreamChunk], blocks: [Block]?, sessionStatus: String?) async throws {
        let body = try Operations.ChatStopStream.Input.Body.json(.init(
            channel: channel,
            chunks: StreamChunk.container(for: chunks),
            ts: ts,
            blocks: blocks,
            sessionStatus: sessionStatus,
        ))
        _ = try await retryingRateLimits {
            try await client.chatStopStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 {
                payload
            } else {
                nil
            }
        }.ok.body.json.checked("chat.stopStream")
    }

    /// Repeats `call` while `rateLimited` finds a 429 response, waiting the seconds in its `Retry-After`.
    private func retryingRateLimits<Output>(
        _ call: () async throws -> Output,
        rateLimited: (Output) -> UndocumentedPayload?,
    ) async throws -> Output {
        var attempt = 1
        while true {
            let output = try await call()
            guard let payload = rateLimited(output), attempt < 3 else {
                return output
            }
            let retryAfter = payload.headerFields
                .first { $0.name.canonicalName == "retry-after" }
                .flatMap { Int($0.value) }
            try await Task.sleep(for: .seconds(retryAfter ?? 1))
            attempt += 1
        }
    }
}
