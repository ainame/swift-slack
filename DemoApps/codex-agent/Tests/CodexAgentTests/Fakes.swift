@testable import CodexAgent
import Foundation
import HTTPTypes
import OpenAPIRuntime
import SlackKit
import Synchronization

/// Answers Web API calls like Slack and records the form-encoded requests.
actor FakeSlack: ClientTransport {
    struct Request: Sendable {
        var method: String
        var fields: [String: String]

        subscript(field: String) -> String? {
            fields[field]
        }
    }

    enum Reply: Sendable {
        case json(String)
        /// The request fails before Slack answers, as a network error does.
        case transportFailure
    }

    struct TransportFailure: Error {}

    static let ts = "1700000000.000100"

    private(set) var requests: [Request] = []
    private var replies: [String: [Reply]] = [:]
    /// Methods whose calls wait until ``release(_:)`` or until they are cancelled, with the waiting calls.
    private var held: [String: [AsyncStream<Void>.Continuation]] = [:]
    private var waiters: [(predicate: @Sendable ([Request]) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func client() async -> any APIProtocol {
        await Slack(transport: self, configuration: .init(token: "xoxb-test")).client
    }

    /// Answers the next calls of `method` with `replies` in order, repeating the last one.
    func reply(to method: String, with replies: Reply...) {
        self.replies[method] = replies
    }

    /// Keeps calls of `method` waiting until ``release(_:)`` or until the calling task is cancelled.
    func hold(_ method: String) {
        held[method] = held[method] ?? []
    }

    /// Lets the held calls of `method` and later ones get their replies.
    func release(_ method: String) {
        for gate in held.removeValue(forKey: method) ?? [] {
            gate.finish()
        }
    }

    /// Answers `conversations.info` with a channel, a code channel when `recordType` is `agent_channel`.
    func channel(recordType: String?, origin: MessageLink? = nil) {
        var properties: [String] = []
        if let recordType {
            properties.append(#""record_channel":{"record_type":"\#(recordType)"}"#)
        }
        if let origin {
            properties.append(#""agent_session":{"origin_link":{"channel_id":"\#(origin.channel)","ts":"\#(origin.ts)"}}"#)
        }
        reply(to: "conversationsInfo", with: .json(#"{"ok":true,"channel":{"id":"C1","properties":{\#(properties.joined(separator: ","))}}}"#))
    }

    func requests(_ method: String) -> [Request] {
        requests.filter { $0.method == method }
    }

    /// Waits until the recorded requests satisfy `predicate`.
    func wait(until predicate: @escaping @Sendable ([Request]) -> Bool) async {
        guard !predicate(requests) else { return }
        await withCheckedContinuation { waiters.append((predicate, $0)) }
    }

    /// Waits until a request to `method` satisfies `predicate`.
    func waitFor(_ method: String, where predicate: @escaping @Sendable (Request) -> Bool = { _ in true }) async {
        await wait { $0.contains { $0.method == method && predicate($0) } }
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
        requests.append(Request(method: operationID, fields: Self.fields(of: form)))
        let ready = waiters.filter { $0.predicate(requests) }
        waiters.removeAll { $0.predicate(requests) }
        for waiter in ready {
            waiter.continuation.resume()
        }

        if held[operationID] != nil {
            let (gate, continuation) = AsyncStream.makeStream(of: Void.self)
            held[operationID]?.append(continuation)
            for await _ in gate {}
            try Task.checkCancellation()
        }

        let reply: Reply
        if var queued = replies[operationID], !queued.isEmpty {
            reply = queued.count > 1 ? queued.removeFirst() : queued[0]
            replies[operationID] = queued
        } else if operationID == "conversationsInfo" {
            reply = .json(#"{"ok":true,"channel":{"id":"C1"}}"#)
        } else {
            reply = .json(#"{"ok":true,"channel":"C1","ts":"\#(Self.ts)"}"#)
        }
        switch reply {
        case let .json(body):
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(body))
        case .transportFailure:
            throw TransportFailure()
        }
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

/// A backend whose turns the test drives. Each turn yields a line of text, optionally asks a question, and
/// then waits until the test releases its session or the turn is stopped.
struct ScriptedBackend: AgentBackend {
    let probe = BackendProbe()
    var asksQuestion = false

    func respond(
        to prompt: String,
        in session: SessionKey,
        tools: any AgentTools,
    ) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [probe, asksQuestion] in
                let release = await probe.start(session, prompt: prompt)
                continuation.yield(.text("Hello"))
                if asksQuestion {
                    do {
                        _ = try await tools.askUser("Which?", options: ["A", "B"])
                        await probe.record(session, "answered")
                    } catch {
                        await probe.record(session, "question ended")
                    }
                }
                for await _ in release {}
                continuation.finish()
            }
            continuation.onTermination = { [probe] termination in
                task.cancel()
                if case .cancelled = termination {
                    Task { await probe.record(session, "cancelled") }
                }
            }
        }
    }
}

actor BackendProbe {
    private(set) var prompts: [SessionKey: [String]] = [:]
    private(set) var events: [SessionKey: [String]] = [:]
    private var releases: [SessionKey: AsyncStream<Void>.Continuation] = [:]
    private var waiters: [(predicate: @Sendable (BackendProbe.Snapshot) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []

    struct Snapshot {
        var prompts: [SessionKey: [String]]
        var events: [SessionKey: [String]]
    }

    func start(_ session: SessionKey, prompt: String) -> AsyncStream<Void> {
        let (release, continuation) = AsyncStream.makeStream(of: Void.self)
        releases[session] = continuation
        prompts[session, default: []].append(prompt)
        signal()
        return release
    }

    func record(_ session: SessionKey, _ event: String) {
        events[session, default: []].append(event)
        signal()
    }

    /// Lets the session's running turn finish.
    func release(_ session: SessionKey) {
        releases.removeValue(forKey: session)?.finish()
    }

    func waitForStart(of session: SessionKey, count: Int = 1) async {
        await wait { ($0.prompts[session]?.count ?? 0) >= count }
    }

    func waitFor(_ event: String, in session: SessionKey) async {
        await wait { $0.events[session]?.contains(event) == true }
    }

    private func wait(until predicate: @escaping @Sendable (Snapshot) -> Bool) async {
        guard !predicate(snapshot) else { return }
        await withCheckedContinuation { waiters.append((predicate, $0)) }
    }

    private var snapshot: Snapshot {
        Snapshot(prompts: prompts, events: events)
    }

    private func signal() {
        let snapshot = snapshot
        let ready = waiters.filter { $0.predicate(snapshot) }
        waiters.removeAll { $0.predicate(snapshot) }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
