import Foundation
import Logging
import OpenAPIRuntime
import SlackKit

/// Concrete Slack tool handlers for one Codex turn, scoped to its session and the person it answers.
///
/// Once Slack has stopped the session, the tools fail without calling Slack.
struct SlackAgentTools: Sendable {
    var transferFile: @Sendable (URL, Data) async throws -> Void = { try await SlackFileTransfer.send(to: $0, data: $1) }

    func uploadFile(_ file: WorkspaceUpload, title: String?) async throws -> UploadedFile {
        try checkCodeChannel()
        guard !file.data.isEmpty, file.data.count <= WorkspaceUpload.maximumBytes, (title?.count ?? 0) <= 200 else {
            throw AgentToolError(description: "Upload a file of at most 20 MiB with a title of at most 200 characters.")
        }
        let upload = try await client.filesGetUploadURLExternal(body: .json(.init(
            length: file.data.count, filename: file.filename,
        ))).ok.body.json.checked("files.getUploadURLExternal")
        try checkSession()
        guard let id = upload.fileId, !id.isEmpty, let address = upload.uploadUrl, let url = URL(string: address) else {
            throw AgentToolError(description: "Slack did not return the upload destination and file ID.")
        }
        try SlackFileTransfer.validate(url)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await transferFile(url, file.data)
                return true
            }
            group.addTask {
                await producer.waitForStop()
                try Task.checkCancellation()
                return false
            }
            defer { group.cancelAll() }
            guard try await group.next() == true else {
                throw CancellationError()
            }
        }
        try checkSession()
        let result = try await client.filesCompleteUploadExternal(body: .json(.init(
            files: OpenAPIArrayContainer(unvalidatedValue: [["id": id, "title": title ?? file.filename]]),
            channelId: session.channel,
        ))).ok.body.json.checked("files.completeUploadExternal")
        try checkSession()
        logger.info("Uploaded Code channel file", metadata: ["channel": "\(session.channel)", "file_id": "\(id)"])
        return UploadedFile(fileID: id, permalink: result.files?.first(where: { $0.id == id })?.permalink)
    }

    func showWorkspace(_ workspace: SessionWorkspaces.Workspace) async throws {
        try checkCodeChannel()
        let result = try await client.setCodeChannelProperties(
            channelId: session.channel,
            properties: .init(contextBarItems: [
                .init(key: "repository", label: URL(filePath: workspace.repository).lastPathComponent, icon: .folder, itemType: .info),
                .init(key: "branch", label: workspace.branch, icon: .branch, itemType: .info),
                .init(key: "checkout", label: workspace.path, icon: .terminal, itemType: .info),
            ]),
        )
        if let warning = result.warning {
            logger.warning("Workspace context: \(warning)")
        }
    }

    let client: any APIProtocol
    let session: SessionKey
    /// The thread the turn replies in, or `nil` for a top-level reply in a code channel.
    let replyThreadTs: String?
    let userId: String
    let identity: BotIdentity?
    let questions: PendingQuestions
    /// Whether the person has renamed the session, so the agent leaves the title alone.
    let isTitledByUser: @Sendable () async -> Bool
    /// The turn's stop signal, which tells whether Slack has stopped the session.
    let producer: TurnProducer
    var lifecycle = CodeChannelLifecycle()
    var messageTs: String?
    var origin: MessageLink?
    var logger = Logger(label: "codex-agent.tools")
    var onCodeChannel: @Sendable (String) async -> Void = { _ in }
    var endSession: @Sendable () async -> Void = {}

    var currentCodeChannel: String? {
        if case .codeChannel = session {
            session.channel
        } else {
            nil
        }
    }

    func startCodeChannel(name: String) async throws -> String {
        try checkSession()
        guard let originTs = messageTs ?? session.threadTs else {
            if case .codeChannel = session {
                return session.channel
            }
            throw AgentToolError(description: "There is no origin message for this conversation.")
        }
        let created = try await lifecycle.create(
            name: name, from: session, messageTs: originTs, client: client, producer: producer, logger: logger,
        )
        try checkSession()
        if created.shouldLaunch {
            await onCodeChannel(created.channel)
        }
        return created.channel
    }

    func publishView(_ view: CodeChannel.View) async throws {
        try checkCodeChannel()
        let response = try await client.setCodeChannelView(channelId: session.channel, view: view)
        if let warning = response.warning {
            logger.warning("Code channel view: \(warning)")
        }
    }

    func archiveCodeChannel(summary: String) async throws {
        try checkCodeChannel()
        let posted = try await client.chatPostMessage(body: .json(.init(
            channel: session.channel, text: summary,
        ))).ok.body.json.checked("chat.postMessage")
        guard let ts = posted.ts else { throw AgentToolError(description: "Slack did not return the summary timestamp.") }
        try checkSession()
        let properties = try await client.setCodeChannelProperties(
            channelId: session.channel, properties: .init(summaryMessage: .init(messageTs: ts)),
        )
        if let warning = properties.warning {
            logger.warning("Code channel summary: \(warning)")
        }
        try checkSession()
        let createdWithOrigin = await lifecycle.channels.origin(of: session.channel) != nil
        try checkSession()
        _ = try await client.agentsConversationsArchive(body: .json(.init(
            channelId: session.channel,
            summaryMessageTs: origin != nil || createdWithOrigin ? ts : nil,
        )))
        .ok.body.json.checked("agents.conversations.archive")
        await endSession()
    }

    func approve(_ request: AgentApproval) async -> Bool {
        // Never ask someone to approve details that the Slack message cannot show in full.
        guard producer.reason == nil, request.question.count <= 2800 else {
            logger.warning("Approval rejected before asking", metadata: ["session": "\(session)", "reason": producer.reason == nil ? "details_too_long" : "turn_stopped"])
            return false
        }
        do {
            let answer = try await askUser(request.question, options: ["Approve", "Deny"])
            let approved = answer == "Approve" && producer.reason == nil
            logger.info("Approval resolved", metadata: ["session": "\(session)", "decision": approved ? "approve" : "deny"])
            return approved
        } catch {
            logger.warning("Approval failed", metadata: ["session": "\(session)", "error": "\(error)"])
            return false
        }
    }

    private func checkCodeChannel() throws {
        try checkSession()
        guard case .codeChannel = session else {
            throw AgentToolError(description: "Start a code channel first; views and archiving belong to that channel.")
        }
    }

    func setTitle(_ title: String) async throws {
        try checkSession()
        guard await !isTitledByUser() else {
            throw AgentToolError(description: "The person named this conversation; keep their title.")
        }
        try checkSession()
        do {
            _ = try await client.agentsSessionsRename(body: .json(.init(
                channelId: session.channel,
                title: String(title.prefix(200)),
                threadTs: session.threadTs,
            ))).ok.body.json.checked("agents.sessions.rename")
        } catch let error as SlackAPIError {
            logger.warning("Could not rename the conversation", metadata: ["session": "\(session)", "error": "\(error)"])
            throw AgentToolError(description: "\(error). Keep the existing title and continue the task; do not create another channel to recover from a rename failure.")
        }
    }

    /// Reads the thread the turn replies in. A top-level reply in a code channel has no thread, so `thread`
    /// reads the channel, which is that session's conversation.
    func readSlack(_ scope: SlackReadScope, limit: Int) async throws -> String {
        try checkSession()
        let messages: [Message] = if scope == .thread, let replyThreadTs {
            try await Array(ConversationHistory.replies(
                channel: session.channel,
                threadTs: replyThreadTs,
                client: client,
            ).suffix(limit))
        } else {
            try await ConversationHistory.channelMessages(channel: session.channel, limit: limit, client: client)
        }
        let lines = messages.compactMap { ConversationHistory.line(for: $0, identity: identity) }
        // Keep the tool result small; the conversation may be long.
        let transcript = lines.joined(separator: "\n\n")
        return transcript.isEmpty ? "There are no messages." : String(transcript.suffix(8000))
    }

    func askUser(_ question: String, options: [String]) async throws -> String {
        try checkSession()
        let id = UUID().uuidString
        let posted = try await client.chatPostMessage(body: .json(.init(
            blocks: SlackUI.questionBlocks(id: id, question: question, options: options, userId: userId),
            channel: session.channel,
            text: question,
            threadTs: replyThreadTs,
        ))).ok.body.json
        guard posted.ok else {
            // `invalid_blocks` explains itself in response_metadata.messages.
            let details = [posted.error ?? "unknown_error"] + (posted.responseMetadata?.messages ?? [])
            throw SlackAPIError(method: "chat.postMessage", code: details.joined(separator: ": "))
        }

        // Waiting for the person, not working: `suspended` shows that the agent needs input.
        await setStatus("suspended")
        let stopWaiter = Task { [producer, questions, session] in
            await producer.waitForStop()
            guard !Task.isCancelled else { return }
            await questions.cancel(session)
        }
        defer { stopWaiter.cancel() }
        let outcome: Result<String, any Error>
        do {
            outcome = try await .success(questions.wait(
                id: id,
                session: session,
                options: options,
                userId: userId,
                isCancelled: { [producer] in producer.reason != nil },
            ))
        } catch {
            outcome = .failure(error)
        }
        stopWaiter.cancel()
        await stopWaiter.value
        // A stopped session takes no status or message updates; Slack has already ended it.
        try checkSession()
        await setStatus("processing")

        if let ts = posted.ts {
            try checkSession()
            let summary = switch outcome {
            case let .success(choice): "<@\(userId)> chose *\(choice)*."
            case .failure: "_No answer._"
            }
            _ = try? await client.chatUpdate(body: .json(.init(
                blocks: SlackUI.questionResultBlocks(question: question, summary: summary),
                channel: session.channel,
                text: "\(question) \(summary)",
                ts: ts,
            )))
        }
        return try outcome.get()
    }

    private func checkSession() throws {
        if producer.reason != nil || Task.isCancelled {
            throw AgentToolError(description: "The person stopped the turn.")
        }
    }

    private func setStatus(_ status: String) async {
        guard producer.reason == nil, !Task.isCancelled else { return }
        _ = try? await client.agentsSessionsSetStatus(body: .json(.init(
            channelId: session.channel,
            status: status,
            threadTs: session.threadTs,
        )))
    }
}
