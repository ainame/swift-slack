import Logging

/// Records the messages logged through the loggers it makes, so tests can check what was logged.
final class LogRecorder: Sendable {
    private struct Entry {
        let level: Logger.Level
        let message: String
    }

    private let stream: AsyncStream<Entry>
    private let continuation: AsyncStream<Entry>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func makeLogger() -> Logger {
        Logger(label: "test") { [continuation] _ in Handler(continuation: continuation) }
    }

    /// Stops recording and returns the warnings logged so far. Call it once per recorder.
    func warnings() async -> [String] {
        continuation.finish()
        var warnings: [String] = []
        for await entry in stream where entry.level == .warning {
            warnings.append(entry.message)
        }
        return warnings
    }

    private struct Handler: LogHandler {
        let continuation: AsyncStream<Entry>.Continuation
        var metadata: Logger.Metadata = [:]
        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event: LogEvent) {
            continuation.yield(Entry(level: event.level, message: event.message.description))
        }
    }
}
