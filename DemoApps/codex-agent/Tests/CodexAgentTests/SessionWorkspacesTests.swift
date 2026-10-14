@testable import CodexAgent
import Foundation
import Testing

struct SessionWorkspacesTests {
    @Test
    func `concurrent workspace managers allocate one checkout for a channel`() async throws {
        try await withRepository { source, root in
            let first = try SessionWorkspaces(source: source.path, root: root.path)
            let second = try SessionWorkspaces(source: source.path, root: root.path)
            let key = SessionKey.codeChannel(channel: "C1")
            async let a = first.allocation(for: key)
            async let b = second.allocation(for: key)
            let (left, right) = try await (a, b)
            #expect(left == right)
            let list = try gitOutput(["worktree", "list", "--porcelain"], in: source)
            #expect(list.components(separatedBy: "branch refs/heads/slack-code/C1/work").count == 2)
        }
    }

    @Test
    func `registered topic worktrees preserve the original checkout and other sessions`() async throws {
        try await withRepository { source, root in
            let originalHEAD = try gitOutput(["rev-parse", "HEAD"], in: source)
            try Data("uncommitted source".utf8).write(to: source.appending(path: "README"))
            let workspaces = try SessionWorkspaces(source: source.path, root: root.path)
            let first = try await workspaces.allocation(for: .codeChannel(channel: "C1"))
            let second = try await workspaces.allocation(for: .codeChannel(channel: "C2"))
            #expect(first.path == root.appending(path: "code-C1").path)
            #expect(first.branch == "slack-code/C1/work")
            #expect(first.branch != second.branch)
            #expect(try gitOutput(["worktree", "list", "--porcelain"], in: source).contains(first.path))
            #expect(first.commonDirectory == second.commonDirectory)
            try Data("changed".utf8).write(to: URL(filePath: first.path).appending(path: "README"))
            try git(["add", "README"], in: URL(filePath: first.path))
            try git(["commit", "-m", "session change"], in: URL(filePath: first.path))
            #expect(try gitOutput(["rev-parse", "HEAD"], in: source) == originalHEAD)
            #expect(try gitOutput(["branch", "--show-current"], in: source) == "main")
            #expect(try String(contentsOf: source.appending(path: "README"), encoding: .utf8) == "uncommitted source")
            #expect(try String(contentsOf: URL(filePath: second.path).appending(path: "README"), encoding: .utf8) == "original")
        }
    }

    @Test
    func `restart restores the same worktree branch dirty files commits and conversation`() async throws {
        try await withRepository { source, root in
            let key = SessionKey.codeChannel(channel: "C1")
            let first = try SessionWorkspaces(source: source.path, root: root.path)
            let workspace = try await first.allocation(for: key)
            try await first.saveConversation("conversation-123", for: key)
            try Data("pending change".utf8).write(to: URL(filePath: workspace.path).appending(path: "README"))
            let restarted = try SessionWorkspaces(source: source.path, root: root.path)
            let recovered = try await restarted.allocation(for: key)
            #expect(recovered.path == workspace.path)
            #expect(recovered.branch == workspace.branch)
            #expect(recovered.conversationID == "conversation-123")
            #expect(try String(contentsOf: URL(filePath: recovered.path).appending(path: "README"), encoding: .utf8) == "pending change")
            #expect(try await first.allocation(for: key) == recovered)
        }
    }

    @Test(arguments: ["missing", "branch", "corrupt", "path", "channel", "git_directory", "symlink", "conversation"])
    func `invalid persisted state reports recovery without replacing work`(damage: String) async throws {
        try await withRepository { source, root in
            let key = SessionKey.codeChannel(channel: "C1")
            let manager = try SessionWorkspaces(source: source.path, root: root.path)
            let record = try await manager.allocation(for: key)
            try await manager.saveConversation("conversation-123", for: key)
            let path = URL(filePath: record.path)
            let state = root.appending(path: ".sessions/C1.json")
            switch damage {
            case "missing": try FileManager.default.moveItem(at: path, to: root.appending(path: "preserved"))
            case "branch": try git(["checkout", "-b", "different"], in: path)
            case "corrupt": try Data("broken".utf8).write(to: state)
            case "conversation":
                var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: state)) as? [String: Any])
                json.removeValue(forKey: "conversation_id")
                try JSONSerialization.data(withJSONObject: json).write(to: state)
            case "symlink":
                try FileManager.default.moveItem(at: path, to: root.appending(path: "preserved"))
                try FileManager.default.createSymbolicLink(at: path, withDestinationURL: root.appending(path: "preserved"))
            default:
                var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: state)) as? [String: Any])
                json[damage] = damage == "channel" ? "C2" : source.path
                try JSONSerialization.data(withJSONObject: json).write(to: state)
            }
            let snapshot = try Data(contentsOf: state)
            let restarted = try SessionWorkspaces(source: source.path, root: root.path)
            do {
                _ = try await restarted.allocation(for: key)
                Issue.record("Reused invalid session state")
            } catch let error as AgentToolError {
                #expect(error.description.contains("git worktree"))
                #expect(error.description.contains("No replacement"))
            }
            #expect(try Data(contentsOf: state) == snapshot)
            #expect(try gitOutput(["worktree", "list", "--porcelain"], in: source).components(separatedBy: "worktree ").count == 3)
        }
    }

    @Test
    func `legacy clone directories are untouched and ordinary threads cannot allocate`() async throws {
        try await withRepository { source, root in
            let legacy = root.appending(path: "code-4331-old-uuid")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try Data("unpublished work".utf8).write(to: legacy.appending(path: "keep"))
            let manager = try SessionWorkspaces(source: source.path, root: root.path)
            _ = try await manager.allocation(for: .codeChannel(channel: "C1"))
            #expect(try String(contentsOf: legacy.appending(path: "keep"), encoding: .utf8) == "unpublished work")
            await #expect(throws: AgentToolError.self) {
                try await manager.allocation(for: .thread(channel: "C1", threadTs: "1.2"))
            }
        }
    }

    @Test
    func `sandbox Git roots exclude original index hooks configuration and unrelated refs`() async throws {
        try await withRepository { source, root in
            let manager = try SessionWorkspaces(source: source.path, root: root.path)
            let record = try await manager.allocation(for: .codeChannel(channel: "C1"))
            let roots = try #require(record.gitWritableRoots)
            #expect(roots.worktreeDirectory == record.gitDirectory)
            #expect(roots.objectsDirectory == record.commonDirectory + "/objects")
            #expect(roots.branchRefs == record.commonDirectory + "/refs/heads/slack-code/C1")
            #expect(roots.branchLogs == record.commonDirectory + "/logs/refs/heads/slack-code/C1")
            #expect(roots.paths.count == 4)
            #expect(!roots.paths.contains(record.commonDirectory))
            #expect(roots.paths.contains(record.commonDirectory + "/refs/heads/slack-code/C1"))
            #expect(!roots.paths.contains(source.path))
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
        try git(["init", "-b", "main"], in: source)
        try git(["add", "."], in: source)
        try git(["commit", "-m", "initial"], in: source)
        try await body(source, temporary.appending(path: "sessions"))
    }

    private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
