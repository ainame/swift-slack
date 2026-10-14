/// The four writable Git metadata paths of one session worktree. Shared config, hooks and unrelated refs
/// are deliberately absent. These are derived from the existing session record, not persisted separately.
struct WorktreeGitRoots: Sendable {
    let worktreeDirectory: String
    let objectsDirectory: String
    let branchRefs: String
    let branchLogs: String

    var paths: [String] {
        [worktreeDirectory, objectsDirectory, branchRefs, branchLogs]
    }
}
