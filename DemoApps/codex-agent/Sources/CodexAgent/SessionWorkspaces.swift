#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// Persistent Code channel worktrees. Records live outside the writable checkout; never remove old clones.
actor SessionWorkspaces {
    struct Workspace: Codable, Sendable, Equatable {
        let version: Int
        let channel: String
        let repository: String
        let commonDirectory: String
        let path: String
        let branch: String
        var gitDirectory: String?
        var conversationID: String?
        var conversationReady = false

        enum CodingKeys: String, CodingKey {
            case version, channel, repository, path, branch
            case commonDirectory = "common_directory"
            case gitDirectory = "git_directory"
            case conversationID = "conversation_id"
            case conversationReady = "conversation_ready"
        }

        /// Git's shared config, hooks, main index and unrelated refs remain outside writable roots.
        var gitWritableRoots: WorktreeGitRoots? {
            guard let gitDirectory else { return nil }
            let common = URL(filePath: commonDirectory)
            let namespace = branch.split(separator: "/").dropLast().joined(separator: "/")
            return WorktreeGitRoots(
                worktreeDirectory: gitDirectory,
                objectsDirectory: common.appending(path: "objects").path,
                branchRefs: common.appending(path: "refs/heads/" + namespace).path,
                branchLogs: common.appending(path: "logs/refs/heads/" + namespace).path,
            )
        }
    }

    private let source: URL
    private let root: URL

    init(source: String, root: String) throws {
        self.source = URL(filePath: source).standardizedFileURL.resolvingSymlinksInPath()
        self.root = URL(filePath: root).standardizedFileURL.resolvingSymlinksInPath()
        guard !Self.contains(self.source, path: self.root), !Self.contains(self.root, path: self.source) else {
            throw AgentToolError(description: "CODEX_SESSION_WORKSPACES and CODEX_WORKSPACE must not overlap.")
        }
    }

    func workspace(for key: SessionKey) throws -> String {
        try allocation(for: key).path
    }

    func allocation(for key: SessionKey) throws -> Workspace {
        let channel = try channelID(key)
        return try locked {
            do {
                if let record = try read(channel) {
                    guard record.channel == channel else { throw AgentToolError(description: "Session record belongs to a different channel.") }
                    try validate(record)
                    return record
                }
                try Task.checkCancellation()
                let common = try gitPath(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: source)
                let destination = root.appending(path: "code-" + channel)
                let branch = "slack-code/" + channel + "/work"
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw AgentToolError(description: "An unrecorded checkout already exists at \(destination.path). Preserve it and restore its session record before retrying.")
                }
                // Record intent first. A crash or failed allocation must never cause a second checkout.
                var record = Workspace(
                    version: 1,
                    channel: channel,
                    repository: source.path,
                    commonDirectory: common,
                    path: destination.path,
                    branch: branch,
                )
                try write(record)
                _ = try git(["worktree", "add", "-b", branch, "--", destination.path, "HEAD"], in: source)
                record.gitDirectory = try gitPath(["rev-parse", "--absolute-git-dir"], in: destination)
                try write(record)
                try validate(record)
                // These directories permit a commit without granting all shared Git metadata write access.
                for path in record.gitWritableRoots?.paths ?? [] {
                    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                }
                return record
            } catch {
                throw recovery(channel: channel, error: error)
            }
        }
    }

    func saveConversation(_ id: String, for key: SessionKey) throws {
        let channel = try channelID(key)
        try locked {
            do {
                guard var record = try read(channel), !id.isEmpty else {
                    throw AgentToolError(description: "Missing session record or Codex conversation ID.")
                }
                guard record.channel == channel else { throw AgentToolError(description: "Session record belongs to a different channel.") }
                try validate(record)
                guard record.conversationID == nil || record.conversationID == id else {
                    throw AgentToolError(description: "Another Codex conversation is already recorded for this channel.")
                }
                record.conversationID = id
                record.conversationReady = true
                try write(record)
            } catch { throw recovery(channel: channel, error: error) }
        }
    }

    private func channelID(_ key: SessionKey) throws -> String {
        guard case let .codeChannel(channel) = key, !channel.isEmpty,
              channel.utf8.allSatisfy({ (65 ... 90).contains($0) || (48 ... 57).contains($0) }) else {
            throw AgentToolError(description: "Writable worktrees require a Code channel with an uppercase alphanumeric Slack channel ID.")
        }
        return channel
    }

    private func recordURL(_ channel: String) -> URL {
        root.appending(path: ".sessions/" + channel + ".json")
    }

    private func read(_ channel: String) throws -> Workspace? {
        let url = recordURL(channel)
        guard url.resolvingSymlinksInPath() == url else {
            throw AgentToolError(description: "The session record became a symlink.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
    }

    private func write(_ record: Workspace) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: recordURL(record.channel), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL(record.channel).path)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        let state = root.appending(path: ".sessions")
        guard root.resolvingSymlinksInPath() == root, state.resolvingSymlinksInPath() == state else {
            throw AgentToolError(description: "The workspace root or session state directory became a symlink. Restore CODEX_SESSION_WORKSPACES before retrying.")
        }
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(state.appending(path: "allocation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AgentToolError(description: "Cannot open the workspace allocation lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw AgentToolError(description: "Cannot lock workspace state.") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private func validate(_ record: Workspace) throws {
        let directory = URL(filePath: record.path)
        guard record.conversationReady == (record.conversationID != nil), record.conversationID != "" else {
            throw AgentToolError(description: "Recorded Codex conversation state is incomplete or invalid.")
        }
        guard record.version == 1, record.repository == source.path,
              record.path == root.appending(path: "code-" + record.channel).path,
              record.branch == "slack-code/" + record.channel + "/work",
              directory.resolvingSymlinksInPath() == directory,
              FileManager.default.fileExists(atPath: directory.path),
              let gitDirectory = record.gitDirectory else {
            throw AgentToolError(description: "Session state is incomplete, changed, or its worktree is missing.")
        }
        let common = try gitPath(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: source)
        guard common == record.commonDirectory,
              try gitPath(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: directory) == common,
              try gitPath(["rev-parse", "--absolute-git-dir"], in: directory) == gitDirectory,
              URL(filePath: gitDirectory).resolvingSymlinksInPath().path == gitDirectory,
              Self.contains(URL(filePath: common).appending(path: "worktrees"), path: URL(filePath: gitDirectory)),
              try gitPath(["rev-parse", "--show-toplevel"], in: directory) == directory.path,
              try git(["symbolic-ref", "--short", "HEAD"], in: directory) == record.branch else {
            throw AgentToolError(description: "Worktree Git metadata, repository, or topic branch no longer matches its session record.")
        }
        let list = try git(["worktree", "list", "--porcelain", "-z"], in: source)
        guard list.components(separatedBy: "\0\0").contains(where: {
            $0.components(separatedBy: "\0").contains(where: { line in
                line.hasPrefix("worktree ") && URL(filePath: String(line.dropFirst(9))).resolvingSymlinksInPath() == directory
            })
                && $0.components(separatedBy: "\0").contains("branch refs/heads/" + record.branch)
        }) else { throw AgentToolError(description: "Git no longer registers this worktree.") }
        for path in record.gitWritableRoots?.paths ?? [] {
            guard URL(filePath: path).resolvingSymlinksInPath().path == path else {
                throw AgentToolError(description: "A writable Git metadata path became a symlink.")
            }
        }
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw AgentToolError(description: "Cannot inspect the session checkout.")
        }
        for case let entry as URL in entries {
            if entry.lastPathComponent == ".env" {
                throw AgentToolError(description: "The session checkout contains a .env file.")
            }
            if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
               !Self.contains(directory, path: entry.resolvingSymlinksInPath()) {
                throw AgentToolError(description: "The session checkout contains a symlink outside the checkout.")
            }
        }
    }

    private func recovery(channel: String, error: any Error) -> AgentToolError {
        AgentToolError(
            description: "Cannot resume Code channel \(channel): \(error). Preserve all checkouts and commits. Inspect git worktree list --porcelain in CODEX_WORKSPACE and \(recordURL(channel).path); restore the recorded path/branch and use git worktree repair if moved. See README workspace recovery. No replacement was allocated.",
        )
    }

    private func gitPath(_ arguments: [String], in directory: URL) throws -> String {
        try URL(filePath: git(arguments, in: directory)).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AgentToolError(description: "git \(arguments.prefix(2).joined(separator: " ")) failed (exit \(process.terminationStatus)).")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contains(_ directory: URL, path: URL) -> Bool {
        path.path == directory.path || path.path.hasPrefix(directory.path + "/")
    }
}
