@testable import CodexAgent
import Foundation
import Testing

struct WorkspaceSandboxTests {
    @Test
    func `ordinary threads launch with read only permissions and no metadata grants`() throws {
        let arguments = try WorkspaceSandbox.launchArguments(codexPath: nil, workspace: "/repo", repository: nil, stateRoot: nil, gitRoots: [], writable: false)
        #expect(arguments.suffix(2) == ["--config", "default_permissions=\":read-only\""])
        #expect(!arguments.contains(where: { $0.contains("filesystem=") }))
    }

    @Test
    func `worktree profile grants topic metadata while protecting shared state and original checkout`() throws {
        let arguments = try WorkspaceSandbox.launchArguments(
            codexPath: "/bin/codex", workspace: "/sessions/code-C1", repository: "/repo with.dots", stateRoot: "/sessions",
            gitRoots: [
                "/repo with.dots/.git/worktrees/code-C1",
                "/repo with.dots/.git/objects",
                "/repo with.dots/.git/refs/heads/slack-code/C1",
                "/repo with.dots/.git/logs/refs/heads/slack-code/C1",
            ], writable: true,
        )
        let table = try #require(arguments.first { $0.hasPrefix("permissions.slack-code-worktree.filesystem=") })
        #expect(table.contains("\"/repo with.dots\" = \"read\""))
        #expect(table.contains("\"/repo with.dots/.git\" = \"read\""))
        #expect(table.contains("\"/sessions\" = \"read\""))
        #expect(table.contains("\"/sessions/code-C1\" = \"write\""))
        #expect(table.contains("\"/repo with.dots/.git/worktrees/code-C1\" = \"write\""))
        #expect(arguments.contains("permissions.slack-code-worktree.network.enabled=false"))
        #expect(!table.contains("refs/heads/main"))
    }
}
