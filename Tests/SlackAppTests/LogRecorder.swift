import Foundation
import Logging

/// Records the messages logged through the loggers it makes, so tests can check what was logged.
final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(level: Logger.Level, message: String)] = []

    var warnings: [String] {
        lock.withLock { entries.filter { $0.level == .warning }.map(\.message) }
    }

    func makeLogger() -> Logger {
        Logger(label: "test") { _ in Handler(recorder: self) }
    }

    fileprivate func record(_ level: Logger.Level, _ message: String) {
        lock.withLock { entries.append((level, message)) }
    }

    private struct Handler: LogHandler {
        let recorder: LogRecorder
        var metadata: Logger.Metadata = [:]
        var logLevel: Logger.Level = .trace

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(event: LogEvent) {
            recorder.record(event.level, event.message.description)
        }
    }
}
