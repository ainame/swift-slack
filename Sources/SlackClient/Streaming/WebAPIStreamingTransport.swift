#if WebAPI_Chat
import Foundation
import OpenAPIRuntime
import SlackBlockKit

/// Streams one message through the generated Web API methods.
///
/// A call that Slack rate limits (HTTP 429) is retried after its `Retry-After` delay, up to three attempts,
/// unless Slack has ended the session meanwhile. When the task is cancelled during the delay, the call throws
/// ``RateLimitedCallCancelled`` instead, so the sender sends its parts with the closing calls.
struct WebAPIStreamingTransport: StreamingMessageTransport {
    let client: any APIProtocol
    let channel: String
    /// The thread to reply in, or `nil` to omit `thread_ts` and stream a top-level message.
    let threadTs: String?
    let recipient: StreamingMessage.Recipient?
    let taskDisplay: StreamingMessage.TaskDisplay
    let sessionStatus: String?

    static let maximumAttempts = 3

    func start(chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws -> String {
        let body = try Operations.ChatStartStream.Input.Body.json(.init(
            channel: channel,
            chunks: Self.container(for: chunks),
            threadTs: threadTs,
            recipientUserId: recipient?.userId,
            recipientTeamId: recipient?.teamId,
            taskDisplayMode: taskDisplay.rawValue,
        ))
        let response = try await retryingRateLimits(stopSignal: stopSignal) {
            try await client.chatStartStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 { payload } else { nil }
        }.ok.body.json
        try Self.check("chat.startStream", ok: response.ok, error: response.error)
        guard let ts = response.ts else {
            throw StreamingMessage.Error(method: "chat.startStream", code: "missing_ts")
        }
        return ts
    }

    func append(ts: String, chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws {
        let body = try Operations.ChatAppendStream.Input.Body.json(.init(
            channel: channel,
            chunks: Self.container(for: chunks),
            ts: ts,
        ))
        let response = try await retryingRateLimits(stopSignal: stopSignal) {
            try await client.chatAppendStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 { payload } else { nil }
        }.ok.body.json
        try Self.check("chat.appendStream", ok: response.ok, error: response.error)
    }

    func stop(
        ts: String,
        chunks: [StreamingMessage.Part],
        blocks: [Block]?,
        stopSignal: SessionStopSignal,
    ) async throws {
        let body = try Operations.ChatStopStream.Input.Body.json(.init(
            channel: channel,
            chunks: Self.container(for: chunks),
            ts: ts,
            blocks: blocks,
            sessionStatus: sessionStatus,
        ))
        let response = try await retryingRateLimits(stopSignal: stopSignal) {
            try await client.chatStopStream(body: body)
        } rateLimited: {
            if case let .undocumented(429, payload) = $0 { payload } else { nil }
        }.ok.body.json
        try Self.check("chat.stopStream", ok: response.ok, error: response.error)
    }

    /// Repeats `call` while `rateLimited` finds a 429 response, waiting the seconds in its `Retry-After`.
    ///
    /// Once `stopSignal` is raised, the wait ends and no retry starts. When the task is cancelled, the wait ends
    /// and ``RateLimitedCallCancelled`` is thrown instead of retrying.
    private func retryingRateLimits<Output>(
        stopSignal: SessionStopSignal,
        _ call: () async throws -> Output,
        rateLimited: (Output) -> UndocumentedPayload?,
    ) async throws -> Output {
        var attempt = 1
        while true {
            try await stopSignal.check()
            let output = try await call()
            guard let payload = rateLimited(output), attempt < Self.maximumAttempts else {
                return output
            }
            let retryAfter = payload.headerFields
                .first { $0.name.canonicalName == "retry-after" }
                .flatMap { Int($0.value) }
            let delay = Duration.seconds(retryAfter ?? 1)
            let retryAt = ContinuousClock.now + delay
            try await stopSignal.sleep(for: delay)
            if Task.isCancelled {
                // A cancelled task does not retry; Slack rejected the call, so the sender can resend its parts.
                throw RateLimitedCallCancelled(retryAt: retryAt)
            }
            attempt += 1
        }
    }

    /// Swift Slack decodes `"ok": false` responses without throwing, so streaming checks them itself.
    private static func check(_ method: String, ok: Bool, error: String?) throws {
        guard ok else {
            throw StreamingMessage.Error(method: method, code: error ?? "unknown_error")
        }
    }

    /// Converts parts to the untyped container the generated request bodies take, or `nil` when empty.
    ///
    /// slack-api-ref declares `chunks` as an array without an item schema, so the generated bodies take an
    /// `OpenAPIArrayContainer`.
    static func container(for parts: [StreamingMessage.Part]) throws -> OpenAPIArrayContainer? {
        guard !parts.isEmpty else { return nil }
        return try JSONDecoder().decode(
            OpenAPIArrayContainer.self,
            from: JSONEncoder().encode(parts.map(Chunk.init)),
        )
    }
}

/// The JSON object for one part in a `chunks` array.
private struct Chunk: Encodable {
    /// Slack limits `task_update` and `plan_update` text fields to 256 characters.
    static let textFieldLimit = 256

    let part: StreamingMessage.Part

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case title
        case status
        case details
        case output
        case sources
        case blocks
        case url
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch part {
        case let .markdown(text):
            try container.encode("markdown_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .task(task):
            try container.encode("task_update", forKey: .type)
            try container.encode(task.id, forKey: .id)
            try container.encode(Self.truncated(task.title), forKey: .title)
            try container.encode(task.status.rawValue, forKey: .status)
            try container.encodeIfPresent(task.details.map(Self.truncated), forKey: .details)
            try container.encodeIfPresent(task.output.map(Self.truncated), forKey: .output)
            if let sources = task.sources {
                var array = container.nestedUnkeyedContainer(forKey: .sources)
                for source in sources {
                    var object = array.nestedContainer(keyedBy: CodingKeys.self)
                    try object.encode("url", forKey: .type)
                    try object.encode(source.text, forKey: .text)
                    try object.encode(source.url, forKey: .url)
                }
            }
        case let .plan(title):
            try container.encode("plan_update", forKey: .type)
            try container.encode(Self.truncated(title), forKey: .title)
        case let .blocks(blocks):
            try container.encode("blocks", forKey: .type)
            try container.encode(blocks, forKey: .blocks)
        }
    }

    private static func truncated(_ value: String) -> String {
        value.count > textFieldLimit ? value.prefix(textFieldLimit - 1) + "…" : value
    }
}
#endif
