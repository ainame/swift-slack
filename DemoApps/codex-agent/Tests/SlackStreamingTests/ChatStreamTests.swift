import SlackKit
@testable import SlackStreaming
import Testing

struct ChatStreamTests {
    let blocks: [Block] = [.divider(DividerBlock())]

    @Test
    func `starts with the first chunks, appends the rest, and stops with the blocks`() async throws {
        let transport = FakeTransport()
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        for word in ["one ", "two ", "three"] {
            continuation.yield(.markdownText(word))
        }
        continuation.finish()

        let ts = try await ChatStream(transport: transport, minimumInterval: .zero)
            .send(chunks, blocks: blocks, sessionStatus: "suspended")

        let calls = await transport.calls
        #expect(ts == FakeTransport.ts)
        #expect(calls.first?.method == "start")
        #expect(calls.last == .init(method: "stop", chunks: calls.last?.chunks ?? [], blocks: blocks, sessionStatus: "suspended"))
        #expect(calls.dropLast().allSatisfy { $0.method != "stop" })
        #expect(text(calls) == "one two three")
    }

    @Test
    func `starts and stops a message when the input is empty`() async throws {
        let transport = FakeTransport()
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        continuation.finish()

        try await ChatStream(transport: transport, minimumInterval: .zero).send(chunks, blocks: blocks)

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdownText(" ")]),
            .init(method: "stop", chunks: [], blocks: blocks),
        ])
    }

    @Test
    func `sends task updates in the order they were yielded`() async throws {
        let transport = FakeTransport()
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        let started = TaskUpdate(id: "t1", title: "Fetch", status: .inProgress)
        let completed = TaskUpdate(id: "t1", title: "Fetch", status: .complete)
        continuation.yield(.taskUpdate(started))
        continuation.yield(.markdownText("done"))
        continuation.yield(.taskUpdate(completed))
        continuation.finish()

        try await ChatStream(transport: transport, minimumInterval: .zero).send(chunks)

        #expect(await transport.calls.flatMap(\.chunks) == [
            .taskUpdate(started), .markdownText("done"), .taskUpdate(completed),
        ])
    }

    @Test
    func `stops the message when the sending task is cancelled`() async throws {
        let transport = FakeTransport()
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        continuation.yield(.markdownText("partial"))

        let sending = Task {
            try await ChatStream(transport: transport, minimumInterval: .zero).send(chunks, blocks: blocks)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        _ = try await sending.value

        let calls = await transport.calls
        #expect(calls.first == .init(method: "start", chunks: [.markdownText("partial")]))
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
    }

    @Test
    func `throws the transport's error`() async {
        let transport = FakeTransport(failing: "append")
        let (chunks, continuation) = AsyncStream.makeStream(of: StreamChunk.self)
        let sending = Task {
            try await ChatStream(transport: transport, minimumInterval: .zero).send(chunks)
        }
        continuation.yield(.markdownText("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdownText("second"))

        await #expect(throws: SlackAPIError.self) {
            try await sending.value
        }
        continuation.finish()
    }

    private func text(_ calls: [FakeTransport.Call]) -> String {
        calls.flatMap(\.chunks).map { chunk in
            guard case let .markdownText(text) = chunk else { return "" }
            return text
        }.joined()
    }
}

private actor FakeTransport: ChatStreamTransport {
    struct Call: Equatable {
        var method: String
        var chunks: [StreamChunk]
        var blocks: [Block]?
        var sessionStatus: String?
    }

    static let ts = "1700000000.000100"

    private(set) var calls: [Call] = []
    private let failingMethod: String?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(failing failingMethod: String? = nil) {
        self.failingMethod = failingMethod
    }

    func start(chunks: [StreamChunk]) async throws -> String {
        try record(Call(method: "start", chunks: chunks))
        return Self.ts
    }

    func append(ts _: String, chunks: [StreamChunk]) async throws {
        try record(Call(method: "append", chunks: chunks))
    }

    func stop(ts _: String, chunks: [StreamChunk], blocks: [Block]?, sessionStatus: String?) async throws {
        try record(Call(method: "stop", chunks: chunks, blocks: blocks, sessionStatus: sessionStatus))
    }

    func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        for waiter in waiters where waiter.count <= calls.count {
            waiter.continuation.resume()
        }
        waiters.removeAll { $0.count <= calls.count }
        if call.method == failingMethod {
            throw SlackAPIError(method: "chat.\(call.method)Stream", code: "rate_limited")
        }
    }
}
