@testable import CodexAgent
import Foundation
import Testing

struct WorkspaceSandboxTests {
    @Test
    func `ordinary threads launch with read only permissions and no metadata grants`() throws {
        let arguments = try WorkspaceSandbox.launchArguments(codexPath: nil, workspace: "/repo", repository: nil, stateRoot: nil, gitRoots: nil, writable: false)
        #expect(arguments.suffix(2) == ["--config", "default_permissions=\":read-only\""])
        #expect(!arguments.contains(where: { $0.contains("filesystem=") }))
    }

    @Test
    func `worktree profile grants topic metadata while protecting shared state and original checkout`() throws {
        let arguments = try WorkspaceSandbox.launchArguments(
            codexPath: "/bin/codex", workspace: "/sessions/code-C1", repository: "/repo with.dots", stateRoot: "/sessions",
            gitRoots: .init(
                worktreeDirectory: "/repo with.dots/.git/worktrees/code-C1",
                objectsDirectory: "/repo with.dots/.git/objects",
                branchRefs: "/repo with.dots/.git/refs/heads/slack-code/C1",
                branchLogs: "/repo with.dots/.git/logs/refs/heads/slack-code/C1",
            ), writable: true,
        )
        let table = try #require(arguments.first { $0.hasPrefix("permissions.slack-code-worktree.filesystem=") })
        #expect(table.contains("\"/repo with.dots\" = \"read\""))
        #expect(table.contains("\"/repo with.dots/.git\" = \"read\""))
        #expect(table.contains("\"/sessions\" = \"read\""))
        #expect(table.contains("\"/sessions/code-C1\" = \"write\""))
        #expect(table.contains("\"/repo with.dots/.git/worktrees/code-C1\" = \"write\""))
        #expect(arguments.contains("permissions.slack-code-worktree.network.enabled=false"))
        #expect(!table.contains("refs/heads/main"))
        #expect(table ==
            "permissions.slack-code-worktree.filesystem={\"/repo with.dots\" = \"read\", \"/repo with.dots/.git\" = \"read\", \"/repo with.dots/.git/logs/refs/heads/slack-code/C1\" = \"write\", \"/repo with.dots/.git/objects\" = \"write\", \"/repo with.dots/.git/refs/heads/slack-code/C1\" = \"write\", \"/repo with.dots/.git/worktrees/code-C1\" = \"write\", \"/sessions\" = \"read\", \"/sessions/code-C1\" = \"write\"}")
    }

    @Test
    func `writable sessions refuse missing Git metadata grants`() {
        #expect(throws: AgentToolError.self) {
            try WorkspaceSandbox.launchArguments(
                codexPath: nil, workspace: "/sessions/code-C1", repository: "/repo", stateRoot: "/sessions",
                gitRoots: nil, writable: true,
            )
        }
    }
}
