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

        let ts = try await makeDelivery(transport, blocks: blocks).send(parts)

        let calls = await transport.calls
        #expect(ts == FakeTransport.ts)
        #expect(calls.first?.method == "start")
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
        #expect(calls.dropLast().allSatisfy { $0.method != "stop" })
        #expect(text(calls) == "one two three")
    }

    @Test
    func `large finished input preserves text while bounding every request`() async throws {
        let transport = FakeTransport()
        let value = String(repeating: "abc", count: 20000)
        try await makeDelivery(transport).send(AsyncStream { continuation in
            continuation.yield(.markdown(value))
            continuation.finish()
        })
        let calls = await transport.calls
        #expect(text(calls) == value)
        #expect(calls.last?.method == "stop")
        for call in calls {
            let count = call.chunks.reduce(0) { total, part in
                if case let .markdown(value) = part {
                    total + value.count
                } else {
                    total
                }
            }
            #expect(count <= 12000)
        }
    }

    @Test
    func `starts and stops a message when the input is empty`() async throws {
        let transport = FakeTransport()

        try await makeDelivery(transport, blocks: blocks).send(AsyncStream<Part> { $0.finish() })

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

        try await makeDelivery(transport).send(AsyncStream { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        })

        #expect(await transport.calls.flatMap(\.chunks) == parts)
    }

    @Test
    func `reads a sequence that is not Sendable`() async throws {
        let transport = FakeTransport()

        try await makeDelivery(transport).send(Words(["a", "b"]).map { Part.markdown($0) })

        #expect(await text(transport.calls) == "ab")
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
            try await makeDelivery(transport, blocks: blocks).send(parts)
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
            try await makeDelivery(transport, blocks: blocks).send(parts)
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
            try await makeDelivery(transport).send(parts)
        }

        #expect(await transport.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func `stops the message without content and rethrows the error when an append fails`(cleanupFails: Bool) async {
        let transport = FakeTransport(failing: cleanupFails ? ["append", "stopOnce"] : ["append"])
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let sending = Task {
            try await makeDelivery(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        // Sendable input iteration is cancelled when delivery fails.
        await transport.waitForCalls(3)
        continuation.yield(.markdown("third"))

        // A failed cleanup stop does not replace the append's error.
        await #expect(throws: StreamingMessage.Error(method: "chat.appendStream", code: "failed")) {
            try await sending.value
        }
        continuation.finish()

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "append", chunks: [.markdown("second")]),
            .init(method: "stopOnce", chunks: []),
        ])
    }

    @Test(arguments: [false, true])
    func `stops a message that the closing start posted without content when the closing stop fails`(
        cleanupFails: Bool,
    ) async {
        // An empty input reaches the closing calls before any start, so they start the message themselves.
        let transport = FakeTransport(failing: cleanupFails ? ["stop", "stopOnce"] : ["stop"])

        await #expect(throws: StreamingMessage.Error(method: "chat.stopStream", code: "failed")) {
            try await makeDelivery(transport, blocks: blocks).send(AsyncStream<Part> { $0.finish() })
        }

        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown(" ")]),
            .init(method: "stop", chunks: [], blocks: blocks),
            .init(method: "stopOnce", chunks: []),
        ])
    }

    @Test
    func `makes no stop when the closing start fails`() async {
        let transport = FakeTransport(failing: ["start"])

        await #expect(throws: StreamingMessage.Error(method: "chat.startStream", code: "failed")) {
            try await makeDelivery(transport, blocks: blocks).send(AsyncStream<Part> { $0.finish() })
        }

        #expect(await transport.calls == [.init(method: "start", chunks: [.markdown(" ")])])
    }

    @Test
    func `finishes the message when the input throws CancellationError but the sending task is not cancelled`() async {
        // Only the sending task's cancellation discards content; an input that ends with this error ends gracefully.
        let transport = FakeTransport()
        let parts = AsyncThrowingStream<Part, any Error> { continuation in
            continuation.yield(.markdown("partial"))
            continuation.finish(throwing: CancellationError())
        }

        await #expect(throws: CancellationError.self) {
            try await makeDelivery(transport, blocks: blocks).send(parts)
        }

        let calls = await transport.calls
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
        #expect(text(calls) == "partial")
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["start", "append"], InputPath.allCases)
    func `stops the message without content when a call completes after the sending task is cancelled`(
        method: String,
        path: InputPath,
    ) async throws {
        // The paused call completes despite the cancellation, so the sender learns the outcome, including the ts.
        let transport = FakeTransport(pausing: method)
        let input = ManualInput()
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(makeDelivery(transport, blocks: blocks), input, through: path)
        }
        await transport.waitForCalls(1)
        if method == "append" {
            await input.yield(.markdown("second"))
            await transport.waitForCalls(2)
        }
        await input.yield(.markdown(" unsent"))
        // This read means the sender has buffered the unsent part.
        await input.waitForReads(method == "append" ? 4 : 3)
        sending.cancel()
        await transport.release()
        await transport.waitForCalls(method == "append" ? 3 : 2)
        await input.finish()

        await #expect(throws: CancellationError.self) { try await sending.value }
        var sent: [FakeTransport.Call] = [.init(method: "start", chunks: [.markdown("first")])]
        if method == "append" {
            sent.append(.init(method: "append", chunks: [.markdown("second")]))
        }
        // The unsent part and the closing blocks are discarded.
        #expect(await transport.calls == sent + [.init(method: "stopOnce", chunks: [])])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], InputPath.allCases)
    func `makes the cleanup stop in the cancelled task under a shield and rethrows the call's error afterwards`(
        cleanupFails: Bool,
        path: InputPath,
    ) async {
        let transport = FakeTransport(
            failing: cleanupFails ? ["append", "stopOnce"] : ["append"],
            pausing: "append",
        )
        let input = ManualInput()
        await input.yield(.markdown("first"))
        let sending = Task { () -> (error: (any Error)?, isCancelled: Bool, isShielded: Bool) in
            var error: (any Error)?
            do {
                _ = try await send(sender(transport, blocks: blocks), input, through: path)
            } catch let thrown {
                error = thrown
            }
            return (error, Task.isCancelled, Task.hasActiveCancellationShield)
        }
        await transport.waitForCalls(1)
        await input.yield(.markdown("second"))
        await transport.waitForCalls(2)
        // The append is in flight when the task is cancelled, and fails once it is answered.
        sending.cancel()
        await transport.release()
        await transport.waitForCalls(3)
        await input.finish()

        let outcome = await sending.value
        // The append's error, rather than `CancellationError` or the cleanup stop's error.
        #expect(outcome.error as? StreamingMessage.Error == StreamingMessage.Error(
            method: "chat.appendStream",
            code: "failed",
        ))
        // The shield ends with the cleanup stop, so the task observes its cancellation again.
        #expect(outcome.isCancelled)
        #expect(!outcome.isShielded)
        // Only the cleanup stop is shielded. It runs in the cancelled delivery task, isolated to the transport
        // actor, yet observes no cancellation; the calls before it would have honored one.
        #expect(await transport.contexts == [
            .init(method: "start", isCancelled: false, isShielded: false),
            .init(method: "append", isCancelled: false, isShielded: false),
            .init(method: "stopOnce", isCancelled: false, isShielded: true),
        ])
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `stops the message without content when the closing start completes after the sending task is cancelled`(
        path: InputPath,
    ) async throws {
        let transport = FakeTransport(pausing: "start")
        let sending = Task {
            try await send(makeDelivery(transport, blocks: blocks), AsyncStream<Part> { $0.finish() }, through: path)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        await transport.release()

        // The start's ts is kept before the cancellation is checked, so the cleanup stop replaces the closing one.
        await #expect(throws: CancellationError.self) { try await sending.value }
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown(" ")]),
            .init(method: "stopOnce", chunks: []),
        ])
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `discards the parts buffered during the minimum interval when the sending task is cancelled`(
        path: InputPath,
    ) async throws {
        let transport = FakeTransport()
        let input = ManualInput()
        let (sleeps, sleepContinuation) = AsyncStream.makeStream(of: Duration.self)
        await input.yield(.markdown("first"))
        let sending = Task {
            let delivery = makeDelivery(transport, blocks: blocks, minimumInterval: .seconds(3600)) { duration in
                sleepContinuation.yield(duration)
                try await Task.sleep(for: duration)
            }
            return try await send(delivery, input, through: path)
        }
        #expect(await sleeps.first { _ in true } == .seconds(3600))
        await input.yield(.markdown("second"))
        // The third read means the sender has buffered the second part.
        await input.waitForReads(3)
        sending.cancel()
        // Delivery notices the cancellation and stops the message while the input, which ignores it, is idle.
        await transport.waitForCalls(2)
        await input.finish()

        await #expect(throws: CancellationError.self) { try await sending.value }
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "stopOnce", chunks: []),
        ])
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `throws CancellationError when the input finishes because the sending task is cancelled`(
        path: InputPath,
    ) async throws {
        // An AsyncStream ends without an error when the task reading it is cancelled.
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        defer { continuation.finish() }
        continuation.yield(.markdown("partial"))
        let sending = Task {
            try await send(makeDelivery(transport, blocks: blocks), parts, through: path)
        }
        await transport.waitForCalls(1)
        sending.cancel()

        await #expect(throws: CancellationError.self) { try await sending.value }
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("partial")]),
            .init(method: "stopOnce", chunks: []),
        ])
    }

    @Test
    func `waits the minimum interval between calls and sends what arrived meanwhile together`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let sending = Task {
            try await makeDelivery(transport, minimumInterval: .milliseconds(200)).send(parts)
        }
        continuation.yield(.markdown("a"))
        await transport.waitForCalls(1)
        for letter in ["b", "c", "d"] {
            continuation.yield(.markdown(letter))
        }
        await transport.waitForCalls(2)
        continuation.finish()
        _ = try await sending.value

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
            try await makeDelivery(transport, blocks: blocks).send(parts)
        }

        #expect(await transport.calls.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `finishes the start in flight but discards the queued parts when Slack ends the session`() async throws {
        let transport = FakeTransport(holding: "start")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await makeDelivery(transport, blocks: blocks).send(parts)
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
            try await makeDelivery(transport, blocks: blocks).send(parts)
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
        let transport = FakeTransport(failing: ["append"], holding: "append")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await makeDelivery(transport, blocks: blocks).send(parts)
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
        let transport = FakeTransport(failing: ["append"], holding: "stopOnce")
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let sending = Task {
            try await makeDelivery(transport, blocks: blocks).send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        await transport.waitForCalls(3)
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await sending.value
        }

        #expect(await transport.calls.map(\.method) == ["start", "append", "stopOnce"])
        #expect(await transport.heldCallWasCancelled == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `throws SessionStopped instead of the cancellation when Slack ends the session during the cleanup stop`(
        path: InputPath,
    ) async throws {
        let transport = FakeTransport(holding: "stopOnce")
        let input = ManualInput()
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(makeDelivery(transport, blocks: blocks), input, through: path)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        // The cleanup stop starts while the input is idle; the input ignores cancellation and ends only now.
        await transport.waitForCalls(2)
        await input.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "stopOnce", chunks: []),
        ])
        // The cleanup stop is shielded from the cancellation, even while it waits for the session stop.
        #expect(await transport.heldCallWasCancelled == false)
        #expect(await transport.contexts.last == .init(method: "stopOnce", isCancelled: false, isShielded: true))
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `makes no cleanup stop when Slack ends the session during a call in a cancelled task`(
        path: InputPath,
    ) async throws {
        let transport = FakeTransport(holding: "append")
        let input = ManualInput()
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(makeDelivery(transport, blocks: blocks), input, through: path)
        }
        await transport.waitForCalls(1)
        await input.yield(.markdown("second"))
        await transport.waitForCalls(2)
        sending.cancel()
        await input.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        #expect(await transport.calls.map(\.method) == ["start", "append"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `stops waiting the minimum interval and discards the queued parts when Slack ends the session`() async throws {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let (sleeps, sleepContinuation) = AsyncStream.makeStream(of: Duration.self)
        let sending = Task {
            try await makeDelivery(transport, blocks: blocks, minimumInterval: .seconds(3600)) { duration in
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

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `a session stop through the delivery before the message starts posts nothing and reads no input`(
        path: InputPath,
    ) async {
        let transport = FakeTransport()
        let input = ManualInput()
        await input.yield(.markdown("first"))
        let delivery = makeDelivery(transport, blocks: blocks)
        await delivery.notifySessionStopped()
        #expect(await delivery.state == .ready)

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await send(delivery, input, through: path)
        }

        #expect(await transport.calls.isEmpty)
        #expect(await input.readCount == 0)
        #expect(await delivery.state == .ended)
        #expect(await delivery.isSessionStopped)
        #expect(await delivery.messageTs == nil)
    }

    @Test
    func `completion atomically observes a previously marked stop`() async throws {
        let delivery = makeDelivery(FakeTransport())
        #expect(try await delivery.begin(stopSignal: SessionStopSignal(), buffer: PartBuffer()))
        await delivery.notifySessionStopped()
        #expect(await delivery.end())
        #expect(await delivery.state == .ended)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["start", "append"], InputPath.allCases)
    func `a session stop through the delivery finishes the call in flight, ignores it, and makes no further call`(
        method: String,
        path: InputPath,
    ) async {
        let transport = FakeTransport(pausing: method)
        let input = ManualInput()
        let delivery = makeDelivery(transport, blocks: blocks)
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(delivery, input, through: path)
        }
        await transport.waitForCalls(1)
        var reads = 3
        if method == "append" {
            await input.yield(.markdown("second"))
            await transport.waitForCalls(2)
            reads += 1
        }
        await input.yield(.markdown("queued"))
        await input.waitForReads(reads)

        await delivery.notifySessionStopped()
        await transport.release()
        // The input ignores cancellation, so it must end for the call to return.
        await input.finish()

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        #expect(await transport.calls.map(\.method) == (method == "start" ? ["start"] : ["start", "append"]))
        // The queued part is discarded, and nothing is sent twice.
        #expect(await text(transport.calls) == (method == "start" ? "first" : "firstsecond"))
        // The start succeeded, so its ts is known even though the call threw.
        #expect(await delivery.messageTs == FakeTransport.ts)
        #expect(await delivery.state == .ended)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a session stop through the delivery ends the minimum interval wait`() async {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        defer { continuation.finish() }
        let (sleeps, sleepContinuation) = AsyncStream.makeStream(of: Duration.self)
        let delivery = makeDelivery(transport, blocks: blocks, minimumInterval: .seconds(3600)) { duration in
            sleepContinuation.yield(duration)
            try await Task.sleep(for: duration)
        }
        let sending = Task {
            try await delivery.send(parts)
        }
        continuation.yield(.markdown("first"))
        #expect(await sleeps.first { _ in true } == .seconds(3600))
        continuation.yield(.markdown("queued"))

        await delivery.notifySessionStopped()

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        #expect(await transport.calls == [.init(method: "start", chunks: [.markdown("first")])])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a session stop through the delivery wakes delivery and cancels an idle Sendable input`() async {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        let delivery = makeDelivery(transport, blocks: blocks)
        let sending = Task {
            try await delivery.send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)

        // The input stays open: only the delivery ends the message.
        await delivery.notifySessionStopped()

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        if case .terminated = continuation.yield(.markdown("never sent")) {} else {
            Issue.record("Input iteration was not cancelled")
        }
        #expect(await transport.calls == [.init(method: "start", chunks: [.markdown("first")])])
        #expect(await delivery.messageTs == FakeTransport.ts)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], InputPath.allCases)
    func `a session stop through the delivery after the input finishes ignores the closing stop in flight`(
        stopFails: Bool,
        path: InputPath,
    ) async {
        let transport = FakeTransport(failing: stopFails ? ["stop"] : [], pausing: "stop")
        let input = ManualInput()
        let delivery = makeDelivery(transport, blocks: blocks)
        await input.yield(.markdown("first"))
        await input.finish()
        let sending = Task {
            try await send(delivery, input, through: path)
        }
        await transport.waitForCalls(2)

        await delivery.notifySessionStopped()
        await transport.release()

        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        // Neither the stop's success nor its failure leads to another call, such as a cleanup stop.
        #expect(await transport.calls.map(\.method) == ["start", "stop"])
        #expect(await delivery.messageTs == FakeTransport.ts)
    }

    @Test(.timeLimit(.minutes(1)))
    func `the deliveryshows the ts while streaming and keeps it when a later call fails`() async {
        let transport = FakeTransport(failing: ["append"], pausing: "append")
        let (parts, continuation) = AsyncStream.makeStream(of: Part.self)
        defer { continuation.finish() }
        let delivery = makeDelivery(transport, blocks: blocks)
        #expect(await delivery.messageTs == nil)
        let sending = Task {
            try await delivery.send(parts)
        }
        continuation.yield(.markdown("first"))
        await transport.waitForCalls(1)
        continuation.yield(.markdown("second"))
        await transport.waitForCalls(2)

        #expect(await delivery.messageTs == FakeTransport.ts)
        #expect(await delivery.state == .streaming)
        await transport.release()

        await #expect(throws: StreamingMessage.Error.self) { try await sending.value }
        #expect(await delivery.messageTs == FakeTransport.ts)
        #expect(await delivery.state == .ended)
        #expect(await delivery.isSessionStopped == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `the deliverykeeps the ts of a start made with the closing calls when the closing stop fails`(
        path: InputPath,
    ) async {
        // An empty input reaches the closing calls before any start, so they start the message themselves.
        let transport = FakeTransport(failing: ["stop"])
        let delivery = makeDelivery(transport, blocks: blocks)

        let parts = AsyncStream<Part> { $0.finish() }

        await #expect(throws: StreamingMessage.Error(method: "chat.stopStream", code: "failed")) {
            try await send(delivery, parts, through: path)
        }

        #expect(await transport.calls.map(\.method) == ["start", "stop", "stopOnce"])
        #expect(await delivery.messageTs == FakeTransport.ts)
        #expect(await delivery.state == .ended)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `the deliverykeeps the ts of a closing start that completes after the sending task is cancelled`(
        path: InputPath,
    ) async {
        let transport = FakeTransport(pausing: "start")
        let delivery = makeDelivery(transport, blocks: blocks)
        let parts = AsyncStream<Part> { $0.finish() }
        let sending = Task {
            try await send(delivery, parts, through: path)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        await transport.release()

        // The ts is recorded before the cancellation is checked, so the delivery has it and the cleanup stop runs.
        await #expect(throws: CancellationError.self) { try await sending.value }
        #expect(await transport.calls.map(\.method) == ["start", "stopOnce"])
        #expect(await delivery.messageTs == FakeTransport.ts)
        #expect(await delivery.isSessionStopped == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `a session stop through the delivery after the sending task is cancelled skips the cleanup stop`(
        path: InputPath,
    ) async {
        let transport = FakeTransport(pausing: "start")
        let input = ManualInput()
        let delivery = makeDelivery(transport, blocks: blocks)
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(delivery, input, through: path)
        }
        await transport.waitForCalls(1)
        sending.cancel()
        // Slack ends the session while the cancelled start is still in flight.
        await delivery.notifySessionStopped()
        await transport.release()
        await input.finish()

        // The Slack signal takes precedence over the cancellation, and no cleanup stop is made after it.
        await #expect(throws: StreamingMessage.SessionStopped()) { try await sending.value }
        #expect(await transport.calls.map(\.method) == ["start"])
        #expect(await delivery.messageTs == FakeTransport.ts)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `a delivery sends one message, and another send throws AlreadyUsed without reading or calling`(
        path: InputPath,
    ) async throws {
        let transport = FakeTransport(pausing: "start")
        let input = ManualInput()
        let otherInput = ManualInput()
        await otherInput.yield(.markdown("other"))
        await otherInput.finish()
        let delivery = makeDelivery(transport, blocks: blocks)
        await input.yield(.markdown("first"))
        let sending = Task {
            try await send(delivery, input, through: path)
        }
        await transport.waitForCalls(1)

        await #expect(throws: StreamingMessage.Delivery.AlreadyUsed()) {
            try await send(delivery, otherInput, through: path)
        }
        #expect(await delivery.state == .streaming)

        await transport.release()
        await input.finish()
        #expect(try await sending.value == FakeTransport.ts)
        #expect(await delivery.state == .ended)

        // An ended delivery cannot be sent again either, and a stop no longer has any effect.
        await delivery.notifySessionStopped()
        #expect(await delivery.isSessionStopped == false)
        await #expect(throws: StreamingMessage.Delivery.AlreadyUsed()) {
            try await send(delivery, otherInput, through: path)
        }
        #expect(await otherInput.readCount == 0)
        // The rejected sends added nothing to the message.
        #expect(await transport.calls == [
            .init(method: "start", chunks: [.markdown("first")]),
            .init(method: "stop", chunks: [], blocks: blocks),
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func `of two sends of one delivery at the same time, exactly one streams`() async {
        let transport = FakeTransport()
        let delivery = makeDelivery(transport)
        let attempts = ["one", "two"].map { word in
            Task { () -> (any Error)? in
                let parts = AsyncStream<Part> { continuation in
                    continuation.yield(.markdown(word))
                    continuation.finish()
                }
                do {
                    _ = try await delivery.send(parts)
                    return nil
                } catch {
                    return error
                }
            }
        }
        var errors: [(any Error)?] = []
        for attempt in attempts {
            await errors.append(attempt.value)
        }

        #expect(errors.count { $0 == nil } == 1)
        #expect(errors.count { $0 is StreamingMessage.Delivery.AlreadyUsed } == 1)
        // Only the winning send's input reached Slack, once.
        let calls = await transport.calls
        #expect(text(calls) == "one" || text(calls) == "two")
        #expect(calls.count(where: { $0.method == "start" }) == 1)
        #expect(await delivery.state == .ended)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a session stop through one delivery leaves another message alone`() async throws {
        let stopped = FakeTransport()
        let running = FakeTransport()
        let (stoppedParts, stoppedContinuation) = AsyncStream.makeStream(of: Part.self)
        let (runningParts, runningContinuation) = AsyncStream.makeStream(of: Part.self)
        defer { stoppedContinuation.finish() }
        let stoppedControl = makeDelivery(stopped, blocks: blocks)
        let runningControl = makeDelivery(running, blocks: blocks)
        let stopping = Task {
            try await stoppedControl.send(stoppedParts)
        }
        let finishing = Task {
            try await runningControl.send(runningParts)
        }
        stoppedContinuation.yield(.markdown("first"))
        runningContinuation.yield(.markdown("first"))
        await stopped.waitForCalls(1)
        await running.waitForCalls(1)

        await stoppedControl.notifySessionStopped()
        await #expect(throws: StreamingMessage.SessionStopped()) { try await stopping.value }
        runningContinuation.yield(.markdown(" second"))
        runningContinuation.finish()

        #expect(try await finishing.value == FakeTransport.ts)
        #expect(await stopped.calls.map(\.method) == ["start"])
        let calls = await running.calls
        #expect(text(calls) == "first second")
        #expect(calls.last?.method == "stop")
        #expect(calls.last?.blocks == blocks)
        #expect(await runningControl.isSessionStopped == false)
    }

    @Test(.timeLimit(.minutes(1)), arguments: InputPath.allCases)
    func `an input that throws SessionStopped marks the delivery`(path: InputPath) async {
        let transport = FakeTransport()
        let (parts, continuation) = AsyncThrowingStream.makeStream(of: Part.self)
        let delivery = makeDelivery(transport, blocks: blocks)
        continuation.yield(.markdown("first"))
        continuation.finish(throwing: StreamingMessage.SessionStopped())

        await #expect(throws: StreamingMessage.SessionStopped()) {
            try await send(delivery, parts, through: path)
        }

        #expect(await delivery.isSessionStopped)
        #expect(await delivery.state == .ended)
    }

    @Test(.timeLimit(.minutes(1)))
    func `sends a sequence that is not Sendable in the isolation of the actor that sends it`() async throws {
        let transport = FakeTransport()
        let delivery = makeDelivery(transport, blocks: blocks)
        let reader = IsolatedReader()

        let result = try await reader.send(["a", "b"], with: delivery)

        #expect(result.ts == FakeTransport.ts)
        #expect(result.reads == 2)
        #expect(await text(transport.calls) == "ab")
        #expect(await transport.calls.last?.blocks == blocks)
    }

    /// A message streamed through `transport`, the same engine that `makeStreamingMessage` and `streamMessage`
    /// use with the Web API transport.
    private func makeDelivery(
        _ transport: FakeTransport,
        blocks: [Block]? = nil,
        minimumInterval: Duration = .zero,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
    ) -> StreamingMessage.Delivery {
        var sender = StreamingMessageSender(transport: transport, blocks: blocks, minimumInterval: minimumInterval)
        if let sleep {
            sender.sleep = sleep
        }
        return StreamingMessage.Delivery(sender: sender)
    }

    private func send<Parts: AsyncSequence & Sendable>(
        _ delivery: StreamingMessage.Delivery,
        _ parts: Parts,
        through path: InputPath,
    ) async throws -> String where Parts.Element == Part {
        switch path {
        case .sendable:
            try await delivery.send(parts)
        case .callerIsolated:
            try await delivery.send(NotSendable(parts))
        }
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

/// Sends a sequence that is not `Sendable`, which shares state that is not `Sendable` with this actor, so the
/// compiler accepts it only if `send` reads it in this actor's isolation.
private actor IsolatedReader {
    private let reads = ReadCounter()

    /// Returns the message's `ts` and how many parts the sequence produced.
    func send(_ words: [String], with delivery: StreamingMessage.Delivery) async throws -> (ts: String, reads: Int) {
        let ts = try await delivery.send(CountingWords(words: words, counter: reads))
        return (ts, reads.count)
    }
}

private final class ReadCounter {
    var count = 0
}

@available(*, unavailable)
extension ReadCounter: Sendable {}

/// Markdown parts from words, counted in a ``ReadCounter`` in the isolation that reads them.
private struct CountingWords: AsyncSequence {
    typealias Element = StreamingMessage.Part

    final class AsyncIterator: AsyncIteratorProtocol {
        private var words: [String]
        private let counter: ReadCounter

        init(words: [String], counter: ReadCounter) {
            self.words = words
            self.counter = counter
        }

        func next(isolation _: isolated (any Actor)?) async -> StreamingMessage.Part? {
            guard !words.isEmpty else { return nil }
            counter.count += 1
            return .markdown(words.removeFirst())
        }

        func next() async -> StreamingMessage.Part? {
            await next(isolation: nil)
        }
    }

    let words: [String]
    let counter: ReadCounter

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(words: words, counter: counter)
    }
}

@available(*, unavailable)
extension CountingWords: Sendable {}

/// Which `send` overload reads the input: the one that reads a Sendable input in a child task, or the one that
/// reads any input in the caller's isolation.
enum InputPath: CaseIterable, Sendable {
    case sendable
    case callerIsolated
}

/// Hides that `base` is `Sendable`, so that only the caller-isolated overload accepts it.
struct NotSendable<Base: AsyncSequence>: AsyncSequence {
    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    func makeAsyncIterator() -> Base.AsyncIterator {
        base.makeAsyncIterator()
    }
}

@available(*, unavailable)
extension NotSendable: Sendable {}

/// An input that a test feeds by hand.
///
/// Its reads ignore cancellation, like a producer that finishes on its own terms, so a test must end it with
/// ``finish(throwing:)``. It counts reads, so a test knows that the sender has buffered every part read before
/// the latest read.
actor ManualInput: AsyncSequence {
    typealias Element = StreamingMessage.Part

    struct AsyncIterator: AsyncIteratorProtocol {
        let input: ManualInput

        func next() async throws -> StreamingMessage.Part? {
            try await input.read()
        }
    }

    private var parts: [StreamingMessage.Part] = []
    private var isFinished = false
    private var failure: (any Error)?
    private var reader: CheckedContinuation<StreamingMessage.Part?, any Error>?
    private var reads = 0
    private var readWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(input: self)
    }

    /// How many elements the sender has asked for.
    var readCount: Int {
        reads
    }

    func yield(_ part: StreamingMessage.Part) {
        if let reader {
            self.reader = nil
            reader.resume(returning: part)
        } else {
            parts.append(part)
        }
    }

    /// Ends the input after the parts yielded so far, by throwing `error` if one is given.
    func finish(throwing error: (any Error)? = nil) {
        isFinished = true
        failure = error
        if let reader {
            self.reader = nil
            if let error {
                reader.resume(throwing: error)
            } else {
                reader.resume(returning: nil)
            }
        }
    }

    func waitForReads(_ count: Int) async {
        guard reads < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    private func read() async throws -> StreamingMessage.Part? {
        reads += 1
        for waiter in readWaiters where waiter.count <= reads {
            waiter.continuation.resume()
        }
        readWaiters.removeAll { $0.count <= reads }
        if !parts.isEmpty {
            return parts.removeFirst()
        }
        if isFinished {
            if let failure {
                throw failure
            }
            return nil
        }
        return try await withCheckedThrowingContinuation { reader = $0 }
    }
}

actor FakeTransport: StreamingMessageTransport {
    struct Call: Equatable {
        var method: String
        var chunks: [StreamingMessage.Part]
        var blocks: [Block]?
    }

    /// What the task making a call observed when the call reached the transport.
    struct Context: Equatable {
        var method: String
        var isCancelled: Bool
        var isShielded: Bool
    }

    static let ts = "1700000000.000100"

    private(set) var calls: [Call] = []
    /// One entry per call, including calls refused because their task was cancelled.
    private(set) var contexts: [Context] = []
    /// Whether the held call's task was cancelled while Slack had not answered it.
    private(set) var heldCallWasCancelled = false
    private let failingMethods: Set<String>
    private let heldMethod: String?
    private var pausedMethod: String?
    private var pausedCall: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Creates a transport whose `failing` calls fail, and whose `holding` calls are answered only once the
    /// session's stop signal is raised, like a request Slack answers after it has ended the session.
    ///
    /// Methods are named `start`, `append`, `stop`, and `stopOnce` for the cleanup stop. The first `pausing` call
    /// is answered only once the test calls ``release()``, even when its task is cancelled meanwhile, like a
    /// request whose response arrives before the transport notices the cancellation.
    init(
        failing failingMethods: Set<String> = [],
        holding heldMethod: String? = nil,
        pausing pausedMethod: String? = nil,
    ) {
        self.failingMethods = failingMethods
        self.heldMethod = heldMethod
        self.pausedMethod = pausedMethod
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

    func stopOnce(ts _: String, stopSignal: SessionStopSignal) async throws {
        try await record(Call(method: "stopOnce", chunks: []), stopSignal: stopSignal)
    }

    func waitForCalls(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    /// Answers the paused call, or the next one if it has not started yet.
    func release() {
        isReleased = true
        pausedCall?.resume()
        pausedCall = nil
    }

    private func record(_ call: Call, stopSignal: SessionStopSignal) async throws {
        contexts.append(Context(
            method: call.method,
            isCancelled: Task.isCancelled,
            isShielded: Task.hasActiveCancellationShield,
        ))
        // Refuse calls made from a cancelled task, like an HTTP transport, so the tests show that the cleanup stop
        // is shielded from the cancellation.
        try Task.checkCancellation()
        calls.append(call)
        for waiter in waiters where waiter.count <= calls.count {
            waiter.continuation.resume()
        }
        waiters.removeAll { $0.count <= calls.count }
        if call.method == pausedMethod {
            pausedMethod = nil
            if !isReleased {
                await withCheckedContinuation { pausedCall = $0 }
            }
        }
        if call.method == heldMethod {
            await stopSignal.waitUntilRaised()
            heldCallWasCancelled = heldCallWasCancelled || Task.isCancelled
        }
        if failingMethods.contains(call.method) {
            let method = call.method == "stopOnce" ? "stop" : call.method
            throw StreamingMessage.Error(method: "chat.\(method)Stream", code: "failed")
        }
    }
}
