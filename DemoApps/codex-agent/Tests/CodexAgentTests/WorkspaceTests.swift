@testable import CodexAgent
import Foundation
import Testing

struct WorkspaceTests {
    @Test(arguments: [false, true])
    func `allows the app directory and its parent without dotenv`(useParent: Bool) throws {
        try withDirectories { root, app in
            let workspace = useParent ? root : app
            let checked = try CodexAgentApp.checkedWorkspace(workspace.path, appDirectory: app)
            #expect(checked == workspace.path)
        }
    }

    @Test(arguments: [false, true])
    func `rejects the app directory and its parent with dotenv`(useParent: Bool) throws {
        try withDirectories { root, app in
            try Data().write(to: app.appending(path: ".env"))
            let workspace = useParent ? root : app
            #expect(throws: CodexAgentApp.ConfigurationError.self) {
                try CodexAgentApp.checkedWorkspace(workspace.path, appDirectory: app)
            }
        }
    }

    @Test
    func `rejects a workspace with its own dotenv`() throws {
        try withDirectories { root, app in
            let workspace = root.appending(path: "repository")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try Data().write(to: workspace.appending(path: ".env"))
            #expect(throws: CodexAgentApp.ConfigurationError.self) {
                try CodexAgentApp.checkedWorkspace(workspace.path, appDirectory: app)
            }
        }
    }

    @Test
    func `allows a sibling whose name prefixes the app directory`() throws {
        try withDirectories { root, app in
            try Data().write(to: app.appending(path: ".env"))
            let workspace = root.appending(path: "app")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let checked = try CodexAgentApp.checkedWorkspace(workspace.path, appDirectory: app)
            #expect(checked == workspace.path)
        }
    }

    @Test(arguments: [false, true])
    func `resolves symlinks before checking dotenv`(hasDotenv: Bool) throws {
        try withDirectories { root, app in
            let link = root.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
            if hasDotenv {
                try Data().write(to: app.appending(path: ".env"))
                #expect(throws: CodexAgentApp.ConfigurationError.self) {
                    try CodexAgentApp.checkedWorkspace(link.path, appDirectory: app)
                }
            } else {
                let checked = try CodexAgentApp.checkedWorkspace(link.path, appDirectory: app)
                #expect(checked == app.path)
            }
        }
    }

    private func withDirectories(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .resolvingSymlinksInPath()
        let app = root.appending(path: "app-demo")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, app)
    }
}
