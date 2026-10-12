@testable import CodexAgent
import Testing

struct TurnProducerTests {
    @Test(.timeLimit(.minutes(1)))
    func `normal completion needs no stop signal`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        await producer.run { await state.finish(cancelled: Task.isCancelled) }
        #expect(await state.finished)
        #expect(await !state.cancelled)
        #expect(producer.reason == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `stop cancels production while the caller drains closing parts`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        let (parts, continuation) = AsyncStream.makeStream(of: String.self)
        let (events, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        defer { eventContinuation.finish() }

        async let production: Void = producer.run {
            continuation.yield("first")
            for await _ in events {}
            if Task.isCancelled {
                continuation.yield("Stopped")
            }
            await state.finish(cancelled: Task.isCancelled)
            continuation.finish()
        }

        var received: [String] = []
        for await part in parts {
            received.append(part)
            if part == "first" {
                producer.cancel()
            }
            #expect(!Task.isCancelled)
        }
        await production
        #expect(received == ["first", "Stopped"])
        #expect(await state.finished)
        #expect(await state.cancelled)
        #expect(producer.reason == .cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func `parent cancellation joins production cleanup`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        let (started, startContinuation) = AsyncStream.makeStream(of: Void.self)
        let (events, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        defer { eventContinuation.finish() }

        // An explicit parent handle lets the test simulate cancellation of the event handler.
        let parent = Task {
            await producer.run {
                startContinuation.finish()
                for await _ in events {}
                await state.finish(cancelled: Task.isCancelled)
            }
        }
        for await _ in started {}
        parent.cancel()
        await parent.value
        #expect(await state.finished)
        #expect(await state.cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func `delivery failure cancels and joins the producer scope`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        let (started, startContinuation) = AsyncStream.makeStream(of: Void.self)
        let (events, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        defer { eventContinuation.finish() }

        await #expect(throws: DeliveryFailure.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await producer.run {
                        startContinuation.finish()
                        for await _ in events {}
                        await state.finish(cancelled: Task.isCancelled)
                    }
                }
                for await _ in started {}
                throw DeliveryFailure()
            }
        }
        #expect(await state.finished)
        #expect(await state.cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stop before production starts is retained`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        let (events, continuation) = AsyncStream.makeStream(of: Void.self)
        defer { continuation.finish() }
        producer.cancel()
        producer.cancel()
        await producer.run {
            for await _ in events {}
            await state.finish(cancelled: Task.isCancelled)
        }
        #expect(await state.finished)
        #expect(await state.cancelled)
    }
}

extension TurnProducerTests {
    @Test(.timeLimit(.minutes(1)))
    func `a session stop cancels production and is recorded`() async {
        let producer = TurnProducer()
        let state = ProductionState()
        let (started, startContinuation) = AsyncStream.makeStream(of: Void.self)
        let (events, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        defer { eventContinuation.finish() }

        async let production: Void = producer.run {
            startContinuation.finish()
            for await _ in events {}
            await state.finish(cancelled: Task.isCancelled)
        }
        for await _ in started {}
        producer.stopSession()
        await production
        #expect(await state.cancelled)
        #expect(producer.reason == .sessionStopped)
        #expect(producer.isSessionStopped)
    }

    @Test
    func `a session stop replaces a local cancellation, not the other way round`() {
        let cancelledFirst = TurnProducer()
        cancelledFirst.cancel()
        cancelledFirst.stopSession()
        #expect(cancelledFirst.reason == .sessionStopped)

        let stoppedFirst = TurnProducer()
        stoppedFirst.stopSession()
        stoppedFirst.cancel()
        #expect(stoppedFirst.reason == .sessionStopped)
    }
}

private struct DeliveryFailure: Error {}

private actor ProductionState {
    private(set) var finished = false
    private(set) var cancelled = false

    func finish(cancelled: Bool) {
        self.cancelled = cancelled
        finished = true
    }
}
