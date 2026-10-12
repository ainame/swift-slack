import Foundation
import Logging
import SlackKit

/// ``AgentTools`` for one turn, acting in the turn's session for the person it answers.
///
/// Once Slack has stopped the session, the tools fail without calling Slack.
struct SlackAgentTools: AgentTools {
    /// The `ask_user` tool's schema allows two to five options.
    static let maxOptions = 5

    /// The button for option `index`. Slack rejects a block whose elements share an `action_id`.
    static func choiceActionId(_ index: Int) -> String {
        "ask_user_choice_\(index)"
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
        let createdWithOrigin = await lifecycle.hasOrigin(channel: session.channel)
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
            blocks: Self.questionBlocks(id: id, question: question, options: options, userId: userId),
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
                blocks: [.section(SectionBlock(text: TextObject(type: .mrkdwn, text: "\(question)\n\(summary)")))],
                channel: session.channel,
                text: "\(question) \(summary)",
                ts: ts,
            )))
        }
        return try outcome.get()
    }

    /// The question and one button per option, each with its own `action_id` and the question's ID as
    /// its value.
    static func questionBlocks(id: String, question: String, options: [String], userId: String) -> [Block] {
        [
            .section(SectionBlock(text: TextObject(type: .mrkdwn, text: "<@\(userId)> \(question)"))),
            .actions(ActionsBlock(
                elements: options.prefix(maxOptions).enumerated().map { index, option in
                    .button(ButtonElement(
                        text: TextObject(type: .plainText, text: String(option.prefix(75))),
                        actionId: choiceActionId(index),
                        value: id,
                    ))
                },
                blockId: id,
            )),
        ]
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

/// Questions from `ask_user` waiting for a click.
actor PendingQuestions {
    private struct Question {
        let session: SessionKey
        let options: [String]
        let userId: String
        let continuation: CheckedContinuation<String, any Error>
        let timer: Task<Void, Never>
    }

    private let timeout: Duration
    private var questions: [String: Question] = [:]

    init(timeout: Duration = .seconds(600)) {
        self.timeout = timeout
    }

    /// Waits until the person picks an option, the question times out, or its session is stopped.
    ///
    /// `isCancelled` reports a stop that ``cancel(_:)`` handled before this question was registered.
    func wait(
        id: String,
        session: SessionKey,
        options: [String],
        userId: String,
        isCancelled: @Sendable () -> Bool = { false },
    ) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self.finish(id, with: .failure(AgentToolError(description: "The person did not answer.")))
                }
                questions[id] = Question(
                    session: session,
                    options: options,
                    userId: userId,
                    continuation: continuation,
                    timer: timer,
                )
                if isCancelled() {
                    finish(id, with: .failure(AgentToolError(description: "The person stopped the turn.")))
                    return
                }
            }
        } onCancel: {
            Task { await self.finish(id, with: .failure(CancellationError())) }
        }
    }

    enum Answer: Equatable {
        case accepted(String)
        /// Someone other than the person asked tried to answer.
        case notAsked(userId: String)
        /// The question was answered, timed out, or stopped already.
        case expired
    }

    /// Records a click on option `index` of question `id`.
    func answer(id: String, index: Int, userId: String) -> Answer {
        guard let question = questions[id], question.options.indices.contains(index) else {
            return .expired
        }
        guard question.userId == userId else {
            return .notAsked(userId: question.userId)
        }
        let choice = question.options[index]
        finish(id, with: .success(choice))
        return .accepted(choice)
    }

    func isWaiting(id: String) -> Bool {
        questions[id] != nil
    }

    /// Ends the questions of a stopped session, so the waiting tool call returns.
    func cancel(_ session: SessionKey) {
        for (id, question) in questions where question.session == session {
            finish(id, with: .failure(AgentToolError(description: "The person stopped the turn.")))
        }
    }

    private func finish(_ id: String, with result: Result<String, any Error>) {
        guard let question = questions.removeValue(forKey: id) else { return }
        question.timer.cancel()
        question.continuation.resume(with: result)
    }
}

extension Components.Schemas.AgentsSessionsRenameResponse: SlackResponse {}
