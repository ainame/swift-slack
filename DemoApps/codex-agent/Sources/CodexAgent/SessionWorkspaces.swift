import Foundation

/// Clones committed repository content without hardlinks or a shared .git directory. Resumed sessions keep
/// their checkout; the source checkout (including its uncommitted files) is never used as a writable cwd.
actor SessionWorkspaces {
    private let source: URL
    private let root: URL
    private var allocated: [SessionKey: String] = [:]

    init(source: String, root: String) throws {
        self.source = URL(filePath: source).standardizedFileURL.resolvingSymlinksInPath()
        self.root = URL(filePath: root).standardizedFileURL.resolvingSymlinksInPath()
        guard !Self.contains(self.source, path: self.root), !Self.contains(self.root, path: self.source) else {
            throw AgentToolError(description: "CODEX_SESSION_WORKSPACES and CODEX_WORKSPACE must not overlap.")
        }
    }

    func workspace(for key: SessionKey) throws -> String {
        if let existing = allocated[key] {
            try validate(URL(filePath: existing))
            return existing
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        guard root.resolvingSymlinksInPath() == root else {
            throw AgentToolError(description: "The session workspace root became a symlink.")
        }
        // Each process owns its allocations; never trust a pre-existing checkout after an app restart.
        let destination = root.appending(path: Self.name(for: key) + "-" + UUID().uuidString)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["clone", "--no-local", "--no-hardlinks", "--", source.path, destination.path]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw AgentToolError(description: "CODEX_WORKSPACE must be a local Git repository that can be cloned.")
        }
        do {
            // The clone's local origin would otherwise make an accidental push target the developer's repo.
            let removeOrigin = Process()
            removeOrigin.executableURL = process.executableURL
            removeOrigin.arguments = ["-C", destination.path, "remote", "remove", "origin"]
            removeOrigin.environment = process.environment
            removeOrigin.standardOutput = FileHandle.nullDevice
            removeOrigin.standardError = FileHandle.nullDevice
            try removeOrigin.run()
            removeOrigin.waitUntilExit()
            guard removeOrigin.terminationStatus == 0 else {
                throw AgentToolError(description: "Cannot detach the session checkout from its local origin.")
            }
            try validate(destination)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        allocated[key] = destination.path
        return destination.path
    }

    private func validate(_ directory: URL) throws {
        guard root.resolvingSymlinksInPath() == root, directory.resolvingSymlinksInPath() == directory,
              Self.contains(root, path: directory), directory != root else {
            throw AgentToolError(description: "The session checkout must stay inside its workspace root.")
        }
        // A tracked symlink must not expose the developer's checkout or another session to a coding turn.
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

    private static func contains(_ directory: URL, path: URL) -> Bool {
        path.path == directory.path || path.path.hasPrefix(directory.path + "/")
    }

    private static func name(for key: SessionKey) -> String {
        func hex(_ value: String) -> String {
            value.utf8.map { String(format: "%02x", $0) }.joined()
        }
        switch key {
        case let .codeChannel(channel): return "code-" + hex(channel)
        case let .thread(channel, ts): return "thread-" + hex(channel) + "-" + hex(ts)
        }
    }
}
