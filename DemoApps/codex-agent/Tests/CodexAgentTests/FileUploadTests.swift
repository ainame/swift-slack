import Codex
@testable import CodexAgent
import Foundation
import Testing

struct FileUploadTests {
    @Test(arguments: ["http://files.slack.com/upload", "https://evil.example/upload", "https://files.slack.com:8080/upload", "https://user:password@files.slack.com/upload"])
    func `transfer refuses non Slack or insecure destinations`(address: String) throws {
        #expect(throws: AgentToolError.self) { try SlackFileTransfer.validate(#require(URL(string: address))) }
    }

    @Test
    func `reads relative and absolute regular files in the worktree`() throws {
        try withFiles { root in
            let relative = try WorkspaceUpload.read(path: "image.png", workspace: root.path)
            let absolute = try WorkspaceUpload.read(path: root.appending(path: "image.png").path, workspace: root.path)
            #expect(relative.filename == "image.png")
            #expect(relative.data == Data("image bytes".utf8))
            #expect(absolute.data == relative.data)
        }
    }

    @Test(arguments: ["../outside", ".git/config", ".env", ".env.production", "link", "linked/image.png", "missing", "directory", "empty", "oversized"])
    func `rejects files outside the worktree symlinks secrets and invalid sizes`(path: String) throws {
        try withFiles { root in
            try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
            try Data("secret".utf8).write(to: root.appending(path: ".git/config"))
            for name in [".env", ".env.production", "empty"] {
                try Data().write(to: root.appending(path: name))
            }
            try FileManager.default.createDirectory(at: root.appending(path: "directory"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: root.appending(path: "image.png"))
            try FileManager.default.createSymbolicLink(at: root.appending(path: "linked"), withDestinationURL: root)
            let big = root.appending(path: "oversized")
            try Data().write(to: big)
            let handle = try FileHandle(forWritingTo: big)
            try handle.truncate(atOffset: UInt64(WorkspaceUpload.maximumBytes + 1))
            try handle.close()
            #expect(throws: AgentToolError.self) { try WorkspaceUpload.read(path: path, workspace: root.path) }
        }
    }

    @Test
    func `upload is offered only to Code channels and stale readonly calls are refused`() async {
        let ordinary = AgentToolset.specs(for: .thread(channel: "C1", threadTs: "1"))
        #expect(!ordinary.contains {
            if case let .function(tool) = $0 {
                return tool.name == "upload_file"
            }; return false
        })
        let router = ToolRouter()
        await router.install(SlackAgentTools(
            client: FakeSlack().client(),
            session: .codeChannel(channel: "C1"),
            replyThreadTs: nil,
            userId: "U1",
            identity: nil,
            questions: .init(),
            isTitledByUser: { false },
            producer: .init(),
        ))
        #expect(await !router.handle(call()).success)
    }

    @Test
    func `cleared tool router refuses calls without contacting Slack`() async throws {
        try await withUpload { slack, router, _ in
            await router.clear()
            let result = await router.handle(call())
            #expect(!result.success)
            let text = try resultText(result)
            #expect(text == "No turn is running.")
            #expect(await slack.requests("filesGetUploadURLExternal").isEmpty)
        }
    }

    @Test
    func `upload transfers bytes shares only in current Code channel and returns image reference`() async throws {
        try await withUpload { slack, router, transfer in
            let result = await router.handle(call())
            #expect(result.success)
            let text = try resultText(result)
            let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(json["file_id"] as? String == "F123")
            #expect((json["slack_file"] as? [String: String]) == ["id": "F123"])
            #expect(!text.contains("upload/v1"))
            #expect(await transfer.data == Data("image bytes".utf8))
            let get = try #require(await slack.requests("filesGetUploadURLExternal").first)
            #expect(get["filename"] == "image.png")
            #expect(get["length"] == "11")
            let finish = try #require(await slack.requests("filesCompleteUploadExternal").first)
            #expect(finish["channel_id"] == "C1")
            #expect(finish["thread_ts"] == nil)
            let files = try #require(finish["files"])
            let payload = try JSONSerialization.jsonObject(with: Data(files.utf8)) as? [[String: String]]
            #expect(payload == [["id": "F123", "title": "Screenshot"]])
            let view = try JSONDecoder().decode(
                AgentToolset.CodeViewArguments.self,
                from: Data(#"{"type":"block_kit","key":"screenshot","content":"[{\"type\":\"image\",\"alt_text\":\"Screenshot\",\"slack_file\":{\"id\":\"F123\"}}]"}"#.utf8),
            )
            _ = try view.view()
        }
    }

    @Test(arguments: ["get", "transfer", "finish", "destination"])
    func `upload failures return a tool error without sharing unfinished files`(phase: String) async throws {
        try await withUpload { slack, router, transfer in
            switch phase {
            case "get": await slack.reply(to: "filesGetUploadURLExternal", with: .json(#"{"ok":false,"error":"missing_scope"}"#))
            case "finish": await slack.reply(to: "filesCompleteUploadExternal", with: .json(#"{"ok":false,"error":"not_in_channel"}"#))
            case "destination": await slack.reply(to: "filesGetUploadURLExternal", with: .json(#"{"ok":true,"file_id":"F123","upload_url":"https://evil.example/upload"}"#))
            default: await transfer.fail()
            }
            let result = await router.handle(call())
            #expect(!result.success)
            if phase != "finish" {
                #expect(await slack.requests("filesCompleteUploadExternal").isEmpty)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `stopping a session cancels and joins byte transfer before returning`(nativeStop: Bool) async throws {
        let producer = TurnProducer()
        try await withUpload(producer: producer) { slack, router, transfer in
            await transfer.hold()
            let upload = Task { await router.handle(call()) }
            await transfer.waitUntilStarted()
            if nativeStop {
                producer.stopSession()
            } else {
                upload.cancel()
            }
            #expect(await !upload.value.success)
            #expect(await transfer.finished)
            #expect(await slack.requests("filesCompleteUploadExternal").isEmpty)
        }
    }

    private func call() -> DynamicToolCallParams {
        .init(arguments: ["path": "image.png", "title": "Screenshot"], callId: "call", threadId: "thread", tool: "upload_file", turnId: "turn")
    }

    private func resultText(_ response: DynamicToolCallResponse) throws -> String {
        guard case let .inputText(item)? = response.contentItems.first else { throw AgentToolError(description: "Missing tool response") }
        return item.text
    }

    private func withFiles(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("image bytes".utf8).write(to: root.appending(path: "image.png"))
        try body(root)
    }

    private func withUpload(producer: TurnProducer = .init(), _ body: (FakeSlack, ToolRouter, TransferProbe) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("image bytes".utf8).write(to: root.appending(path: "image.png"))
        let slack = FakeSlack()
        await slack.reply(to: "filesGetUploadURLExternal", with: .json(#"{"ok":true,"file_id":"F123","upload_url":"https://files.slack.com/upload/v1/signed"}"#))
        await slack.reply(to: "filesCompleteUploadExternal", with: .json(#"{"ok":true,"files":[{"id":"F123","permalink":"https://example.slack.com/files/F123"}]}"#))
        let transfer = TransferProbe()
        var tools = await SlackAgentTools(
            client: slack.client(),
            session: .codeChannel(channel: "C1"),
            replyThreadTs: nil,
            userId: "U1",
            identity: nil,
            questions: .init(),
            isTitledByUser: { false },
            producer: producer,
        )
        tools.transferFile = { _, data in try await transfer.send(data) }
        let router = ToolRouter(writeWorkspace: root.path)
        await router.install(tools)
        try await body(slack, router, transfer)
    }
}

private actor TransferProbe {
    private(set) var data: Data?
    private(set) var finished = false
    private var failing = false
    private var held = false
    private var started: [CheckedContinuation<Void, Never>] = []
    func fail() {
        failing = true
    }

    func hold() {
        held = true
    }

    func waitUntilStarted() async {
        guard data == nil else { return }
        await withCheckedContinuation { started.append($0) }
    }

    func send(_ data: Data) async throws {
        defer { finished = true }
        self.data = data
        started.forEach { $0.resume() }
        started.removeAll()
        if failing {
            throw AgentToolError(description: "transfer failed")
        }
        if held {
            try await Task.sleep(for: .seconds(600))
        }
    }
}
