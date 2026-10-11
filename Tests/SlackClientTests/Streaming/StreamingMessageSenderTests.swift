import SlackBlockKit
@testable import SlackClient
import Testing

struct StreamingMessageSenderTests {
    typealias Part = StreamingMessage.Part

    let blocks: [Block] = [.divider(DividerBlock())]

    @Test
    func `starts with the first parts, appends the rest, and stops with the blocks`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        for word in ["one ", "two ", "three"] {
            continuation.yield(.markdown(word))
        }
        continuation.finish()

        let ts = try await sender(transport, blocks: blocks).send(parts)

        let calls = await transport.calls
        #expect(ts == FakeTransport.ts)
        #expect(calls.first?.method == "start")
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
        #expect(calls.dropLast().allSatisfy { $0.method != "stop" })
        #expect(text(calls) == "one two three")
    }

    @Test
    func `starts and stops a message when the input is empty`() async throws {
        let transport = FakeTransport()

        try await sender(transport, blocks: blocks).send(AsyncStream<Part> { $0.finish() })

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown(" ")]),
            .init(method: "stop", chunks: [], blocks: blocks),
        ])
    }

    @Test
    func `sends tasks and blocks in the order they were yielded`() async throws {
        let transport = FakeTransport()
        let started = StreamingMessage.TaskUpdate(id: "t1", title: "Fetch", status: .inProgress)
        let completed = StreamingMessage.TaskUpdate(id: "t1", title: "Fetch", status: .complete)
        let parts: [Part] = [.task(started), .markdown("done"), .task(completed), .blocks(blocks)]

        try await sender(transport).send(AsyncStream { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        })

        #expect(await transport.calls.flatMap(\.chunks) == parts)
    }

    @Test
    func `reads a sequence that is not Sendable`() async throws {
        let transport = FakeTransport()

        try await sender(transport).send(Words(["a", "b"]).map { Part.markdown($0) })

        #expect(text(await transport.calls) == "ab")
    }

    @Test
    func `stops the message when the sending task is cancelled, though the transport honors cancellation`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        continuation.yield(.markdown("partial"))

        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        _ = try await sending.value

        let calls = await transport.calls
        #expect(calls.first == .init(method: "start", chunks: [.markdown("partial")]))
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
    }

    @Test
    func `stops the message when the input ends after its producer is cancelled`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let producer = Task {
            defer { continuation.finish() }
            continuation.yield(.markdown("thinking"))
            try? await Task.sleep(for: .seconds(60))
            continuation.yield(.markdown(" _Stopped._"))
        }
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        await transport.waitForCalls(1)
        producer.cancel()
        _ = try await sending.value

        let calls = await transport.calls
        #expect(text(calls) == "thinking _Stopped._")
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
    }

    @Test
    func `stops the message with the parts so far and rethrows when the input throws`() async throws {
        let transport = FakeTransport()
        let parts = AsyncThrowingStream<Part, any Error> { continuation in
            continuation.yield(.markdown("partial"))
            continuation.finish(throwing: InputError())
        }

        await #expect(throws: InputError.self) {
            try await sender(transport, blocks: blocks).send(parts)
        }

        let calls = await transport.calls
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
        #expect(text(calls) == "partial")
    }

    @Test
    func `posts nothing when the input throws before producing anything`() async throws {
        let transport = FakeTransport()
        let parts = AsyncThrowingStream<Part, any Error> { $0.finish(throwing: InputError()) }

        await #expect(throws: InputError.self) {
            try await sender(transport).send(parts)
        }

        #expect(await transport.calls.isEmpty)
    }

    @Test
    func `stops the message without blocks and throws when an append fails`() async {
        let transport = FakeTransport(failing: "append")
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        // The input stops being read at its next part after the failure.
        await transport.waitForCalls(3)
        continuation.yield(.markdown("third"))

        await #expect(throws: StreamingMessage.Error.self) {
            try await sending.value
        }
        continuation.finish()

        let calls = await transport.calls
        #expect(calls.map(\.method) == ["start", "append", "stop"])
        #expect(calls.last == .init(method: "stop", chunks: []))
    }

    @Test
    func `waits the minimum interval between calls and sends what arrived meanwhile together`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, minimumInterval: .milliseconds(200)).send(parts)
        }
        continuation.yield(.markdown("a"))
        await transport.waitForCalls(1)
        for letter in ["b", "c", "d"] {
            continuation.yield(.markdown(letter))
        }
        await transport.waitForCalls(2)
        continuation.finish()
        try await sending.value

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("a")]),
            .init(method: "append", chunks: [.markdown("bcd")]),
            .init(method: "stop", chunks: []),
        ])
    }

    private func sender(
        _ transport: FakeTransport,
        blocks: [Block]? = nil,
        minimumInterval: Duration = .zero,
    ) -> StreamingMessageSender<FakeTransport> {
        StreamingMessageSender(transport: transport, blocks: blocks, minimumInterval: minimumInterval)
    }

    private func text(_ calls: [FakeTransport.Call]) -> String {
        calls.flatMap(\.chunks).map { part in
            guard case let .markdown(text) = part else { return "" }
            return text
        }.joined()
    }
}

private struct InputError: Error {}

/// A sequence of words whose iterator is a class, so neither is `Sendable`.
private struct Words: AsyncSequence {
    final class AsyncIterator: AsyncIteratorProtocol {
        var words: [String]

        init(words: [String]) {
            self.words = words
        }

        func next() async -> String? {
            words.isEmpty ? nil : words.removeFirst()
        }
    }

    let words: [String]

    init(_ words: [String]) {
        self.words = words
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(words: words)
    }
}

@available(*, unavailable)
extension Words: Sendable {}

actor FakeTransport: StreamingMessageTransport {
    struct Call: Equatable {
        var method: String
        var chunks: [StreamingMessage.Part]
        var blocks: [Block]?
    }

    static let ts = "1700000000.000100"

    private(set) var calls: [Call] = []
    private let failingMethod: String?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(failing failingMethod: String? = nil) {
        self.failingMethod = failingMethod
    }

    func start(chunks: [StreamingMessage.Part]) async throws -> String {
        try record(Call(method: "start", chunks: chunks))
        return Self.ts
    }

    func append(ts _: String, chunks: [StreamingMessage.Part]) async throws {
        try record(Call(method: "append", chunks: chunks))
    }

    func stop(ts _: String, chunks: [StreamingMessage.Part], blocks: [Block]?) async throws {
        try record(Call(method: "stop", chunks: chunks, blocks: blocks))
    }

    func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private func record(_ call: Call) throws {
        // Like an HTTP transport, which abandons requests made from a cancelled task.
        try Task.checkCancellation()
        calls.append(call)
        for waiter in waiters where waiter.count <= calls.count {
            waiter.continuation.resume()
        }
        waiters.removeAll { $0.count <= calls.count }
        if call.method == failingMethod {
            throw StreamingMessage.Error(method: "chat.\(call.method)Stream", code: "rate_limited")
        }
    }
}
