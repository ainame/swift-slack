import Foundation

/// Process-local permission profile. Inline TOML preserves absolute path keys (including dots/spaces).
/// Do not grant the common Git directory: it contains shared hooks/config and the original index.
enum WorkspaceSandbox {
    static func launchArguments(codexPath: String?, workspace: String, repository: String?, stateRoot: String?, gitRoots: [String], writable: Bool) throws -> [String] {
        // Older CLIs that do not recognize permission profiles fall back to read-only, never full access.
        var arguments = [codexPath ?? "codex", "app-server", "--listen", "stdio://", "--config", "sandbox_mode=\"read-only\""]
        guard writable else {
            return arguments + ["--config", "default_permissions=\":read-only\""]
        }
        guard let repository, let stateRoot, gitRoots.count == 4 else {
            throw AgentToolError(description: "Writable Code sessions require validated worktree Git metadata.")
        }
        var permissions = [repository: "read", stateRoot: "read", workspace: "write"]
        permissions[URL(filePath: gitRoots[1]).deletingLastPathComponent().path] = "read"
        for root in gitRoots {
            permissions[root] = "write"
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func literal(_ value: String) throws -> String {
            try String(decoding: encoder.encode(value), as: UTF8.self)
        }
        let table = try permissions.keys.sorted().map { key in
            try "\(literal(key)) = \(literal(permissions[key]!))"
        }.joined(separator: ", ")
        arguments += [
            "--config",
            "default_permissions=\"slack-code-worktree\"",
            "--config",
            "permissions.slack-code-worktree.extends=\":workspace\"",
            "--config",
            "permissions.slack-code-worktree.network.enabled=false",
            "--config",
            "permissions.slack-code-worktree.filesystem={\(table)}",
        ]
        return arguments
    }
}
