@testable import CodexAgent
import Foundation
import Testing

struct SessionWorkspacesTests {
    @Test
    func `sessions clone independently and resume their own checkout`() async throws {
        try await withRepository { source, root in
            let workspaces = try SessionWorkspaces(source: source.path, root: root.path)
            let first = try await workspaces.workspace(for: .codeChannel(channel: "C1"))
            let second = try await workspaces.workspace(for: .codeChannel(channel: "C2"))
            #expect(first != second)
            let config = try String(contentsOf: URL(filePath: first).appending(path: ".git/config"), encoding: .utf8)
            #expect(!config.contains(source.path))
            try Data("changed".utf8).write(to: URL(filePath: first).appending(path: "README"))
            #expect(try String(contentsOf: source.appending(path: "README"), encoding: .utf8) == "original")
            #expect(try String(contentsOf: URL(filePath: second).appending(path: "README"), encoding: .utf8) == "original")
            #expect(try await workspaces.workspace(for: .codeChannel(channel: "C1")) == first)
            #expect(try String(contentsOf: URL(filePath: first).appending(path: "README"), encoding: .utf8) == "changed")
        }
    }

    @Test(arguments: [false, true])
    func `rejects tracked dotenv and escaping symlinks`(symlink: Bool) async throws {
        try await withRepository { source, root in
            if symlink {
                try FileManager.default.createSymbolicLink(at: source.appending(path: "escape"), withDestinationURL: source)
            } else {
                try Data().write(to: source.appending(path: ".env"))
            }
            try git(["add", "."], in: source)
            try git(["commit", "-m", "unsafe"], in: source)
            let workspaces = try SessionWorkspaces(source: source.path, root: root.path)
            do {
                _ = try await workspaces.workspace(for: .codeChannel(channel: "C1"))
                Issue.record("Allocated an unsafe checkout")
            } catch is AgentToolError {}
        }
    }

    @Test
    func `rejects overlapping source and session roots`() throws {
        #expect(throws: AgentToolError.self) { try SessionWorkspaces(source: "/tmp/source", root: "/tmp/source/sessions") }
        #expect(throws: AgentToolError.self) { try SessionWorkspaces(source: "/tmp/sessions/source", root: "/tmp/sessions") }
    }

    private func withRepository(_ body: (URL, URL) async throws -> Void) async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
        let source = temporary.appending(path: "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data("original".utf8).write(to: source.appending(path: "README"))
        try git(["init"], in: source)
        try git(["add", "."], in: source)
        try git(["commit", "-m", "initial"], in: source)
        try await body(source, temporary.appending(path: "sessions"))
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "-c", "user.name=Test", "-c", "user.email=test@example.invalid"] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
