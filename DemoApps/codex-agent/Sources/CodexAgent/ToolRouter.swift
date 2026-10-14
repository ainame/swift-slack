import Codex
import Foundation
import Synchronization

/// Routes Codex's tool calls to the running turn's ``AgentTools``. Codex calls the handler registered when
/// the app-server starts, and a session runs one turn at a time, so the current turn's tools are set here.
final class ToolRouter: Sendable {
    private let current = Mutex<(any AgentTools)?>(nil)
    private let writeWorkspace: String?

    init(writeWorkspace: String? = nil) {
        self.writeWorkspace = writeWorkspace
    }

    private func permits(_ directory: String?) -> Bool {
        guard let writeWorkspace else { return false }
        guard let directory else { return true }
        let root = URL(filePath: writeWorkspace).resolvingSymlinksInPath().path
        let path = URL(filePath: directory, relativeTo: URL(filePath: root, directoryHint: .isDirectory))
            .standardizedFileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }

    func approveCommand(_ request: CommandApprovalRequest) async -> ApprovalDecision {
        guard permits(request.workingDirectory), let tools, let command = request.command, !command.isEmpty else { return .deny }
        let details = [command, request.workingDirectory, request.reason]
            .compactMap(\.self).joined(separator: "\n")
        return await tools.approve(.command(details)) ? .approve : .deny
    }

    func approveFiles(_ request: FileChangeApprovalRequest) async -> ApprovalDecision {
        guard permits(request.grantRoot), let tools else { return .deny }
        let details = [request.reason ?? "Codex requested permission to modify files", request.grantRoot ?? writeWorkspace]
            .compactMap(\.self).joined(separator: "\n")
        return await tools.approve(.files(details)) ? .approve : .deny
    }

    var tools: (any AgentTools)? {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    func handle(_ call: DynamicToolCallParams) async -> DynamicToolCallResponse {
        guard let tools else {
            return AgentToolset.reply("No turn is running.", success: false)
        }
        return await AgentToolset.handle(call, tools: tools, workspace: writeWorkspace)
    }
}
