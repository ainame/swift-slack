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

    @Test(.timeLimit(.minutes(1)))
    func `sends the parts buffered during the minimum interval when the sending task is cancelled`() async throws {
        let transport = FakeTransport()
        let input = ManualInput()
        let (sleeps, sleepContinuation) = AsyncStream.makeStream(of: Duration.self)
        await input.yield(.markdown("first"))
        let sending = Task {
            try await sender(transport, blocks: blocks, minimumInterval: .seconds(3600)) { duration in
                sleepContinuation.yield(duration)
                try await Task.sleep(for: duration)
            }.send(input)
        }
        #expect(await sleeps.first { _ in true } == .seconds(3600))
        await input.yield(.markdown("second"))
        // The third read means the sender has buffered the second part.
        await input.waitForReads(3)
        sending.cancel()
        // The input ignores cancellation, so the buffer stays open while the cancelled sender takes the part.
        await transport.waitForCalls(2)
        await input.finish()

        #expect(try await sending.value == FakeTransport.ts)
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "stop", chunks: [.markdown("second")], blocks: blocks),
        ])
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

    @Test
    func `posts nothing when Slack ends the session before the first part`() async {
        let transport = FakeTransport()
        let parts = AsyncThrowingStream<Part, any Error> { $0.finish(throwing: StreamingMessage.SessionStopped()) }

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sender(transport, blocks: blocks).send(parts)
        }

        #expect(await transport.calls.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `finishes the start in flight but discards the queued parts when Slack ends the session`() async throws {
        let transport = FakeTransport(holding: "start")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("queued"))
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls == [.init(method: "start", chunks: [.markdown("first")])])
        #expect(await transport.heldCallWasCancelled == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func `finishes the append in flight and makes no further call when Slack ends the session`() async throws {
        let transport = FakeTransport(holding: "append")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        await transport.waitForCalls(2)
        continuation.yield(.markdown("queued"))
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "append", chunks: [.markdown("second")]),
        ])
        #expect(await transport.heldCallWasCancelled == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func `ignores a call that fails after Slack ends the session and does not stop the message`() async throws {
        let transport = FakeTransport(failing: "append", holding: "append")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        await transport.waitForCalls(2)
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls.map(\.method) == ["start", "append"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `ignores the stop in flight after a failed call when Slack ends the session`() async throws {
        // The failed append closes the buffer, but the input is still read, so the signal still takes effect.
        let transport = FakeTransport(failing: "append", holding: "stop")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await sender(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        await transport.waitForCalls(3)
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls.map(\.method) == ["start", "append", "stop"])
        #expect(await transport.heldCallWasCancelled == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func `stops waiting the minimum interval and discards the queued parts when Slack ends the session`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let (sleeps, sleepContinuation) = AsyncStream.makeStream(of: Duration.self)
        let sending = Task {
            try await sender(transport, blocks: blocks, minimumInterval: .seconds(3600)) { duration in
                sleepContinuation.yield(duration)
                try await Task.sleep(for: duration)
            }.send(parts)
        }
        continuation.yield(.markdown("first"))
        #expect(await sleeps.first { _ in true } == .seconds(3600))
        continuation.yield(.markdown("queued"))
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls == [.init(method: "start", chunks: [.markdown("first")])])
    }

    private func sender(
        _ transport: FakeTransport,
        blocks: [Block]? = nil,
        minimumInterval: Duration = .zero,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
    ) -> StreamingMessageSender<FakeTransport> {
        var sender = StreamingMessageSender(transport: transport, blocks: blocks, minimumInterval: minimumInterval)
        if let sleep {
            sender.sleep = sleep
        }
        return sender
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

/// An input that a test feeds by hand.
///
/// Its reads ignore cancellation, like a producer that finishes on its own terms, and it counts them, so a test
/// knows that the sender has buffered every part read before the latest read.
actor ManualInput: AsyncSequence {
    typealias Element = StreamingMessage.Part

    struct AsyncIterator: AsyncIteratorProtocol {
        let input: ManualInput

        func next() async -> StreamingMessage.Part? {
            await input.read()
        }
    }

    private var parts: [StreamingMessage.Part] = []
    private var isFinished = false
    private var reader: CheckedContinuation<StreamingMessage.Part?, Never>?
    private var reads = 0
    private var readWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(input: self)
    }

    func yield(_ part: StreamingMessage.Part) {
        if let reader {
            self.reader = nil
            reader.resume(returning: part)
        } else {
            parts.append(part)
        }
    }

    func finish() {
        isFinished = true
        reader?.resume(returning: nil)
        reader = nil
    }

    func waitForReads(_ count: Int) async {
        guard reads < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    private func read() async -> StreamingMessage.Part? {
        reads += 1
        for waiter in readWaiters where waiter.count <= reads {
            waiter.continuation.resume()
        }
        readWaiters.removeAll { $0.count <= reads }
        if !parts.isEmpty {
            return parts.removeFirst()
        }
        if isFinished {
            return nil
        }
        return await withCheckedContinuation { reader = $0 }
    }
}

actor FakeTransport: StreamingMessageTransport {
    struct Call: Equatable {
        var method: String
        var chunks: [StreamingMessage.Part]
        var blocks: [Block]?
    }

    static let ts = "1700000000.000100"

    private(set) var calls: [Call] = []
    /// Whether the held call's task was cancelled while Slack had not answered it.
    private(set) var heldCallWasCancelled = false
    private let failingMethod: String?
    private let heldMethod: String?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Creates a transport whose `failing` calls fail, and whose `holding` calls are answered only once the
    /// session's stop signal is raised, like a request Slack answers after it has ended the session.
    init(failing failingMethod: String? = nil, holding heldMethod: String? = nil) {
        self.failingMethod = failingMethod
        self.heldMethod = heldMethod
    }

    func start(chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws -> String {
        try await record(Call(method: "start", chunks: chunks), stopSignal: stopSignal)
        return Self.ts
    }

    func append(ts _: String, chunks: [StreamingMessage.Part], stopSignal: SessionStopSignal) async throws {
        try await record(Call(method: "append", chunks: chunks), stopSignal: stopSignal)
    }

    func stop(
        ts _: String,
        chunks: [StreamingMessage.Part],
        blocks: [Block]?,
        stopSignal: SessionStopSignal,
    ) async throws {
        try await record(Call(method: "stop", chunks: chunks, blocks: blocks), stopSignal: stopSignal)
    }

    func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private func record(_ call: Call, stopSignal: SessionStopSignal) async throws {
        // Like an HTTP transport, which abandons requests made from a cancelled task.
        try Task.checkCancellation()
        calls.append(call)
        for waiter in waiters where waiter.count <= calls.count {
            waiter.continuation.resume()
        }
        waiters.removeAll { $0.count <= calls.count }
        if call.method == heldMethod {
            await stopSignal.waitUntilRaised()
            heldCallWasCancelled = heldCallWasCancelled || Task.isCancelled
        }
        if call.method == failingMethod {
            throw StreamingMessage.Error(method: "chat.\(call.method)Stream", code: "rate_limited")
        }
    }
}
