import Logging

/// Collects what one logger logs, so a test can inspect it without a process-wide `LoggingSystem.bootstrap`.
///
/// Entries go into an `AsyncStream`, whose continuation is safe to yield to from the synchronous
/// `LogHandler.log`, so the handler needs no lock.
struct LogRecorder: Sendable {
    struct Entry: Sendable, Equatable {
        var level: Logger.Level
        var message: String
        /// The logger's metadata merged with the entry's own, as strings.
        var metadata: [String: String]
    }

    let logger: Logger
    private let stream: AsyncStream<Entry>
    private let continuation: AsyncStream<Entry>.Continuation

    init(metadata: Logger.Metadata = [:]) {
        let (stream, continuation) = AsyncStream.makeStream(of: Entry.self)
        var logger = Logger(label: "test") { _ in Handler(continuation: continuation) }
        for (key, value) in metadata {
            logger[metadataKey: key] = value
        }
        self.logger = logger
        self.stream = stream
        self.continuation = continuation
    }

    /// Ends recording and returns the entries. Call it once, after the code under test has returned.
    func entries() async -> [Entry] {
        continuation.finish()
        var entries: [Entry] = []
        for await entry in stream {
            entries.append(entry)
        }
        return entries
    }

    private struct Handler: LogHandler {
        let continuation: AsyncStream<Entry>.Continuation
        var metadata: Logger.Metadata = [:]
        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(
            level: Logger.Level,
            message: Logger.Message,
            metadata: Logger.Metadata?,
            source _: String,
            file _: String,
            function _: String,
            line _: UInt,
        ) {
            let merged = self.metadata.merging(metadata ?? [:]) { $1 }
            continuation.yield(Entry(
                level: level,
                message: message.description,
                metadata: merged.mapValues { "\($0)" },
            ))
        }
    }
}

extension Logger {
    /// Drops everything, for tests that do not inspect logging.
    static let discarding = Logger(label: "test") { _ in SwiftLogNoOpLogHandler() }
}
