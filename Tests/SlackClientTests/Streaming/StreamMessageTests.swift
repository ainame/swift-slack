import Foundation
import HTTPTypes
import OpenAPIRuntime
import SlackBlockKit
@testable import SlackClient
import Testing

/// Streams through the generated client against a fake HTTP transport.
struct StreamMessageTests {
    typealias Part = StreamingMessage.Part

    @Test
    func `sends the start, append, and stop requests Slack expects`() async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let task = StreamingMessage.TaskUpdate(
            id: "t1",
            title: "Search",
            status: .complete,
            sources: [.init(text: "Docs", url: "https://docs.slack.dev")],
        )
        let sending = Task {
            try await client.streamMessage(
                parts,
                channel: "C1",
                threadTs: "1.0",
                recipient: .init(userId: "U1", teamId: "T1"),
                taskDisplay: .plan,
                blocks: [.divider(DividerBlock())],
                sessionStatus: "suspended",
                minimumInterval: .zero,
            )
        }
        continuation.yield(.plan(title: "Plan"))
        await http.waitForRequests(1)
        continuation.yield(.task(task))
        await http.waitForRequests(2)
        continuation.yield(.markdown("done"))
        continuation.finish()

        #expect(try await sending.value == SlackHTTP.ts)
        let requests = await http.requests
        #expect(requests.map(\.operationID) == ["chatStartStream", "chatAppendStream", "chatStopStream"])

        let start = requests[0].fields
        #expect(start["channel"] == "C1")
        #expect(start["thread_ts"] == "1.0")
        #expect(start["recipient_user_id"] == "U1")
        #expect(start["recipient_team_id"] == "T1")
        #expect(start["task_display_mode"] == "plan")
        #expect(try requests[0].chunks() == [["type": "plan_update", "title": "Plan"]])

        #expect(try requests[1].chunks() == [[
            "type": "task_update",
            "id": "t1",
            "title": "Search",
            "status": "complete",
            "sources": [["type": "url", "text": "Docs", "url": "https://docs.slack.dev"]],
        ]])

        let stop = requests[2].fields
        #expect(stop["ts"] == SlackHTTP.ts)
        #expect(stop["session_status"] == "suspended")
        #expect(stop["blocks"]?.contains("divider") == true)
        #expect(try requests[2].chunks() == [["type": "markdown_text", "text": "done"]])
    }

    @Test
    func `retries a rate-limited call after Retry-After`() async throws {
        let http = SlackHTTP(rateLimitedOnce: "chatStartStream")
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.streamMessage(
            [Part.markdown("hi")].async,
            channel: "C1",
            threadTs: "1.0",
            minimumInterval: .zero,
        )

        #expect(await http.requests.map(\.operationID) == ["chatStartStream", "chatStartStream", "chatStopStream"])
    }

    @Test
    func `throws StreamingMessage.Error when Slack answers ok false`() async throws {
        let http = SlackHTTP(failing: "chatStartStream", code: "not_in_channel")
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        await #expect(throws: StreamingMessage.Error(method: "chat.startStream", code: "not_in_channel")) {
            try await client.streamMessage([Part.markdown("hi")].async, channel: "C1", threadTs: "1.0")
        }
    }

    @Test
    func `truncates task and plan text to 256 characters`() throws {
        let long = String(repeating: "a", count: 300)
        let container = try #require(try WebAPIStreamingTransport.container(for: [
            .task(.init(id: "t1", title: long, status: .error, output: long)),
            .plan(title: long),
        ]))
        let objects = container.value.compactMap { $0 as? [String: (any Sendable)?] }
        for (object, key) in [(objects[0], "title"), (objects[0], "output"), (objects[1], "title")] {
            let value = try #require(object[key] as? String)
            #expect(value.count == 256)
            #expect(value.hasSuffix("…"))
        }
    }
}

private extension Array where Element: Sendable {
    var async: AsyncStream<Element> {
        AsyncStream { continuation in
            forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

/// Answers the streaming methods like Slack and records the form-encoded requests.
private actor SlackHTTP: ClientTransport {
    struct Request {
        var operationID: String
        var fields: [String: String]

        /// The `chunks` field, decoded from the JSON string the form encoding puts there.
        func chunks() throws -> NSArray {
            let json = try #require(fields["chunks"])
            return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSArray)
        }
    }

    static let ts = "1700000000.000100"

    private(set) var requests: [Request] = []
    private var rateLimitedOnce: String?
    private let failing: (operationID: String, code: String)?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(rateLimitedOnce: String? = nil, failing operationID: String? = nil, code: String = "") {
        self.rateLimitedOnce = rateLimitedOnce
        failing = operationID.map { ($0, code) }
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var form = ""
        if let body {
            form = try await String(collecting: body, upTo: .max)
        }
        requests.append(Request(operationID: operationID, fields: Self.fields(of: form)))
        for waiter in waiters where waiter.count <= requests.count {
            waiter.continuation.resume()
        }
        waiters.removeAll { $0.count <= requests.count }

        if rateLimitedOnce == operationID {
            rateLimitedOnce = nil
            var response = HTTPResponse(status: .tooManyRequests)
            response.headerFields[HTTPField.Name("Retry-After")!] = "0"
            return (response, nil)
        }
        if let failing, failing.operationID == operationID {
            return Self.json(#"{"ok":false,"error":"\#(failing.code)"}"#)
        }
        return Self.json(#"{"ok":true,"channel":"C1","ts":"\#(Self.ts)"}"#)
    }

    private static func json(_ body: String) -> (HTTPResponse, HTTPBody?) {
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }

    private static func fields(of form: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in form.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
