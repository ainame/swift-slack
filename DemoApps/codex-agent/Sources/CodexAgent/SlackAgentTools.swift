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

    func setTitle(_ title: String) async throws {
        try checkSession()
        guard await !isTitledByUser() else {
            throw AgentToolError(description: "The person named this conversation; keep their title.")
        }
        _ = try await client.agentsSessionsRename(body: .json(.init(
            channelId: session.channel,
            title: String(title.prefix(200)),
            threadTs: session.threadTs,
        ))).ok.body.json.checked("agents.sessions.rename")
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
        let outcome: Result<String, any Error>
        do {
            outcome = try await .success(questions.wait(
                id: id,
                session: session,
                options: options,
                userId: userId,
                isCancelled: { [producer] in producer.isSessionStopped },
            ))
        } catch {
            outcome = .failure(error)
        }
        // A stopped session takes no status or message updates; Slack has already ended it.
        try checkSession()
        await setStatus("processing")

        if let ts = posted.ts {
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
        if producer.isSessionStopped {
            throw AgentToolError(description: "The person stopped the turn.")
        }
    }

    private func setStatus(_ status: String) async {
        guard !producer.isSessionStopped else { return }
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
        try await withCheckedThrowingContinuation { continuation in
            questions[id] = Question(session: session, options: options, userId: userId, continuation: continuation)
            if isCancelled() {
                finish(id, with: .failure(AgentToolError(description: "The person stopped the turn.")))
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.finish(id, with: .failure(AgentToolError(description: "The person did not answer.")))
            }
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
        questions.removeValue(forKey: id)?.continuation.resume(with: result)
    }
}

extension Components.Schemas.AgentsSessionsRenameResponse: SlackResponse {}
