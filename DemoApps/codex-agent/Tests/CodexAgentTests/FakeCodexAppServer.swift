#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import Testing

/// Runs the real swift-codex transport against a local Python stdio fixture.
struct FakeCodexAppServer {
    let root: URL
    let executable: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
        executable = root.appending(path: "codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = try #require(Bundle.module.url(forResource: "app-server", withExtension: "py", subdirectory: "Fixtures"))
        func quote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let wrapper = "#!/bin/sh\nexec /usr/bin/env python3 \(quote(script.path)) \(quote(root.path))\n"
        try wrapper.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func requests(_ method: String) -> [[String: Any]] {
        let file = root.appending(path: "events.jsonl")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: 10).compactMap { line in
            // The writer appends one record at a time; ignore a partial final record while polling.
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  record["method"] as? String == method else { return nil }
            return record
        }
    }

    func waitFor(_ method: String, count: Int = 1) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while requests(method).count < count {
            guard ContinuousClock.now < deadline else {
                throw FixtureTimeout(method: method)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    var exitedProcessCount: Int {
        requests("launched").filter { record in
            guard let pid = record["pid"] as? Int32 else { return false }
            return kill(pid, 0) == -1 && errno == ESRCH
        }.count
    }

    func waitForExit(count: Int = 1) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while exitedProcessCount < count {
            guard ContinuousClock.now < deadline else { throw FixtureTimeout(method: "process exit") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func releaseDrain() throws {
        try Data().write(to: root.appending(path: "release-drain"))
    }

    func cleanup() {
        for process in requests("launched") {
            if let pid = process["pid"] as? Int32, kill(pid, 0) == 0 {
                _ = kill(pid, SIGTERM)
            }
        }
        if requests("launched").count == exitedProcessCount {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private struct FixtureTimeout: Error {
        let method: String
    }
}
