import Logging
import SlackKit
import Synchronization

/// A person's message the agent may answer, from a `message` or an `app_mention` event.
struct IncomingMessage: Sendable {
    enum Source: Sendable {
        case message
        case mention
        case command
    }

    let source: Source
    /// The event's ID, which Slack keeps when it retries a delivery.
    let eventId: String
    let channel: String
    let isDirectMessage: Bool
    let ts: String
    let threadTs: String?
    let userId: String
    /// The text to answer, without the mention that addressed the bot.
    let text: String
    let teamId: String
}

/// Decides which messages become turns, in which session, and where the reply goes.
///
/// - A direct message starts or continues the session of its thread.
/// - In a Slack Code channel, every person's message is for the agent: top-level messages and thread replies,
///   with or without a mention, share the channel's session. Thread replies are answered in their thread.
/// - In other channels, a mention starts or continues the session of its thread, and a thread reply without
///   a mention continues a thread the agent takes part in.
///
/// A message that mentions the bot arrives twice, as `message` and as `app_mention`, and Slack retries events
/// it thinks were not received. Each message and event therefore turns into at most one turn.
///
/// Routing looks the channel up before the turn starts, so a stop can arrive while a message is still on its
/// way. ``start(_:client:)`` and ``ask(_:client:)`` register each message as a ``RoutingAttempts/Attempt``
/// before they return, and ``stop(channel:threadTs:)`` discards the matching attempts before it stops the
/// running turns. Messages that arrive after the stop start turns as usual.
actor TurnRouter {
    enum Decision: Sendable, Equatable {
        case answer(AgentResponder.Turn)
        /// The person is not in `ALLOWED_USER_IDS`; tell them so where the reply would go.
        case notAllowed(AgentResponder.Turn)
    }

    /// A card's "Ask about this" button, pressed on a reply.
    struct CardQuestion: Sendable {
        let question: String
        let channel: String
        /// The reply's thread, or `nil` for a top-level reply in a code channel.
        let threadTs: String?
        /// The reply's `ts`.
        let messageTs: String
        let userId: String
        let teamId: String
    }

    nonisolated let attempts = RoutingAttempts()
    private let responder: AgentResponder
    private let channels: ChannelClassifier
    private let isAllowed: @Sendable (String) -> Bool
    private let logger: Logger
    private var recentEvents = RecentKeys(capacity: 1000)
    private var recentMessages = RecentKeys(capacity: 1000)

    init(
        responder: AgentResponder,
        channels: ChannelClassifier,
        isAllowed: @escaping @Sendable (String) -> Bool,
        logger: Logger,
    ) {
        self.responder = responder
        self.channels = channels
        self.isAllowed = isAllowed
        self.logger = logger
    }

    /// Routes and answers `message` in a task, and returns at once: in HTTP mode, swift-slack answers the event
    /// request only after the handler returns, and Slack retries events that take longer than three seconds.
    @discardableResult
    nonisolated func start(_ message: IncomingMessage, client: any APIProtocol) -> Task<Void, Never> {
        // Registered before the task starts, so a stop that arrives first still finds it.
        let attempt = attempts.begin(channel: message.channel, threadTs: message.threadTs, ts: message.ts)
        return Task {
            defer { attempts.end(attempt) }
            switch await route(message, attempt: attempt, client: client) {
            case let .answer(turn)?:
                await responder.handle(turn, client: client, attempt: attempt)
            case let .notAllowed(turn)?:
                await postNotAllowed(turn, attempt: attempt, client: client)
            case nil:
                break
            }
        }
    }

    /// Posts a card's question where the reply went and answers it, in a task like ``start(_:client:)``.
    @discardableResult
    nonisolated func ask(_ card: CardQuestion, client: any APIProtocol) -> Task<Void, Never> {
        let attempt = attempts.begin(channel: card.channel, threadTs: card.threadTs, ts: card.messageTs)
        return Task {
            defer { attempts.end(attempt) }
            let destination = await destination(
                channel: card.channel,
                threadTs: card.threadTs,
                messageTs: card.messageTs,
                client: client,
            )
            guard !attempt.isCancelled else { return }
            do {
                // Post the question so the conversation shows what the agent is answering.
                let posted = try await client.chatPostMessage(body: .json(.init(
                    channel: card.channel,
                    text: "<@\(card.userId)> asked: \(card.question)",
                    threadTs: destination.replyThreadTs,
                ))).ok.body.json.checked("chat.postMessage")
                await responder.handle(AgentResponder.Turn(
                    session: destination.session,
                    replyThreadTs: destination.replyThreadTs,
                    messageTs: posted.ts ?? card.messageTs,
                    prompt: card.question,
                    userId: card.userId,
                    teamId: card.teamId,
                    origin: destination.origin,
                ), client: client, attempt: attempt)
            } catch {
                logger.warning("Failed to post the card's question", metadata: ["error": "\(error)"])
            }
        }
    }

    /// Handles Slack's `agent_session_stopped`: discards the messages still being routed in the stopped channel
    /// or thread, then stops the turns already running there.
    func stop(channel: String, threadTs: String?) async {
        attempts.cancel(channel: channel, threadTs: threadTs)
        await responder.stop(channel: channel, threadTs: threadTs)
    }

    /// Returns what to do with `message`, or `nil` to ignore it or when a stop discarded `attempt`. It may look
    /// up the channel and the thread, so call it outside the event handler.
    func route(
        _ message: IncomingMessage,
        attempt: RoutingAttempts.Attempt? = nil,
        client: any APIProtocol,
    ) async -> Decision? {
        guard recentEvents.insert(message.eventId) else { return nil }
        let identity = await responder.identity
        // The app's own messages, including its streamed replies, must not start turns.
        guard message.userId != identity?.userId else { return nil }

        let turn: AgentResponder.Turn
        if message.isDirectMessage {
            turn = threadTurn(for: message)
        } else {
            // A message that mentions the bot also arrives as app_mention, which answers it.
            if message.source == .message, identity?.isMentioned(in: message.text) == true {
                return nil
            }
            let kind = await channels.kind(of: message.channel, client: client)
            guard attempt?.isCancelled != true else { return nil }
            switch kind {
            case let .codeChannel(origin):
                turn = AgentResponder.Turn(
                    session: .codeChannel(channel: message.channel),
                    replyThreadTs: message.threadTs,
                    messageTs: message.ts,
                    prompt: message.text,
                    userId: message.userId,
                    teamId: message.teamId,
                    origin: origin,
                )
            case .other, nil:
                guard message.source != .command else { return nil }
                // A failed lookup answers as in any channel; the next message looks the channel up again.
                turn = threadTurn(for: message)
                if message.source == .message {
                    guard message.threadTs != nil, isAllowed(message.userId),
                          await responder.shouldAnswerThreadReply(in: turn.session, client: client) else {
                        return nil
                    }
                }
            }
        }
        guard attempt?.isCancelled != true,
              recentMessages.insert("\(message.channel)/\(message.ts)") else {
            return nil
        }
        return isAllowed(message.userId) ? .answer(turn) : .notAllowed(turn)
    }

    /// The session and reply destination for a card's "Ask about this" button, pressed on a reply in
    /// `channel`. `threadTs` is the reply's thread, or `nil` for a top-level reply in a code channel.
    func destination(
        channel: String,
        threadTs: String?,
        messageTs: String,
        client: any APIProtocol,
    ) async -> (session: SessionKey, replyThreadTs: String?, origin: MessageLink?) {
        if case let .codeChannel(origin) = await channels.kind(of: channel, client: client) {
            return (.codeChannel(channel: channel), threadTs, origin)
        }
        let threadTs = threadTs ?? messageTs
        return (.thread(channel: channel, threadTs: threadTs), threadTs, nil)
    }

    private func postNotAllowed(
        _ turn: AgentResponder.Turn,
        attempt: RoutingAttempts.Attempt,
        client: any APIProtocol,
    ) async {
        logger.info("Ignoring a message from a user not in ALLOWED_USER_IDS", metadata: ["user": "\(turn.userId)"])
        guard !attempt.isCancelled else { return }
        do {
            _ = try await client.chatPostEphemeral(body: .json(.init(
                channel: turn.session.channel,
                text: "Sorry, this agent only answers the people it is set up for.",
                threadTs: turn.replyThreadTs,
                user: turn.userId,
            ))).ok.body.json.checked("chat.postEphemeral")
        } catch {
            logger.warning("Failed to post the not-allowed notice", metadata: ["error": "\(error)"])
        }
    }

    private func threadTurn(for message: IncomingMessage) -> AgentResponder.Turn {
        let threadTs = message.threadTs ?? message.ts
        return AgentResponder.Turn(
            session: .thread(channel: message.channel, threadTs: threadTs),
            replyThreadTs: threadTs,
            messageTs: message.ts,
            prompt: message.text,
            userId: message.userId,
            teamId: message.teamId,
        )
    }
}

/// The messages and card questions being routed to a turn, which a stop must catch before they start one.
///
/// An attempt stays registered until its turn ends or routing drops it, so the set holds only work in progress.
/// Cancelling discards attempts that already exist; later ones are unaffected.
final class RoutingAttempts: Sendable {
    final class Attempt: Sendable {
        let channel: String
        let threadTs: String?
        let ts: String
        private let cancelled = Mutex(false)

        fileprivate init(channel: String, threadTs: String?, ts: String) {
            self.channel = channel
            self.threadTs = threadTs
            self.ts = ts
        }

        var isCancelled: Bool {
            cancelled.withLock(\.self)
        }

        fileprivate func cancel() {
            cancelled.withLock { $0 = true }
        }

        /// A stop without `threadTs` covers the whole channel. One with `threadTs` covers a message in that
        /// thread and the thread's parent, whose reply would start the thread's session.
        fileprivate func matches(channel: String, threadTs stoppedThreadTs: String?) -> Bool {
            guard self.channel == channel else { return false }
            guard let stoppedThreadTs else { return true }
            return threadTs == stoppedThreadTs || ts == stoppedThreadTs
        }
    }

    private let attempts = Mutex<[ObjectIdentifier: Attempt]>([:])

    func begin(channel: String, threadTs: String?, ts: String) -> Attempt {
        let attempt = Attempt(channel: channel, threadTs: threadTs, ts: ts)
        attempts.withLock { $0[ObjectIdentifier(attempt)] = attempt }
        return attempt
    }

    func end(_ attempt: Attempt) {
        _ = attempts.withLock { $0.removeValue(forKey: ObjectIdentifier(attempt)) }
    }

    func cancel(channel: String, threadTs: String?) {
        attempts.withLock { attempts in
            for attempt in attempts.values where attempt.matches(channel: channel, threadTs: threadTs) {
                attempt.cancel()
            }
        }
    }

    var count: Int {
        attempts.withLock(\.count)
    }

    var isEmpty: Bool {
        attempts.withLock(\.isEmpty)
    }
}

/// Tells Slack Code channels from other channels with `conversations.info`.
///
/// A code channel's `properties.record_channel.record_type` is `agent_channel`. The answer is cached: for good
/// when the channel is a code channel, and for `negativeLifetime` when it is not. A failed lookup is not
/// cached, so the next message tries again.
actor ChannelClassifier {
    enum Kind: Sendable, Equatable {
        /// A code channel, with the message it was started from when Slack reports one.
        case codeChannel(origin: MessageLink?)
        case other
    }

    private let negativeLifetime: Duration
    private let logger: Logger
    private var known: [String: (kind: Kind, expiry: ContinuousClock.Instant?)] = [:]
    /// Lookups in progress, which concurrent messages in the same channel share.
    private var lookups: [String: Task<Kind?, Never>] = [:]

    init(negativeLifetime: Duration = .seconds(600), logger: Logger) {
        self.negativeLifetime = negativeLifetime
        self.logger = logger
    }

    /// The channel's kind, or `nil` when Slack could not tell.
    func kind(of channel: String, client: any APIProtocol) async -> Kind? {
        if let entry = known[channel], entry.expiry.map({ ContinuousClock.now < $0 }) ?? true {
            return entry.kind
        }
        if let lookup = lookups[channel] {
            return await lookup.value
        }
        let lookup = Task { [logger] () -> Kind? in
            do {
                let response = try await client.conversationsInfo(body: .json(.init(channel: channel)))
                    .ok.body.json.checked("conversations.info")
                return Self.kind(of: response.channel)
            } catch {
                logger.warning("Failed to look up the channel", metadata: ["channel": "\(channel)", "error": "\(error)"])
                return nil
            }
        }
        lookups[channel] = lookup
        let kind = await lookup.value
        lookups[channel] = nil
        if let kind {
            known[channel] = (kind, kind == .other ? ContinuousClock.now + negativeLifetime : nil)
        }
        return kind
    }

    static func kind(of conversation: Conversation?) -> Kind {
        guard let properties = conversation?.properties,
              properties.recordChannel?.recordType == "agent_channel" else {
            return .other
        }
        let link = properties.agentSession?.originLink
        let origin = link.flatMap { link in
            link.channelId.flatMap { channel in link.ts.map { MessageLink(channel: channel, ts: $0) } }
        }
        return .codeChannel(origin: origin)
    }
}

/// The most recent keys seen, up to `capacity`, forgetting the oldest first.
struct RecentKeys {
    let capacity: Int
    private var keys: Set<String> = []
    private var order: [String] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Records `key` and returns whether it is new.
    mutating func insert(_ key: String) -> Bool {
        guard keys.insert(key).inserted else { return false }
        order.append(key)
        if order.count > capacity {
            keys.remove(order.removeFirst())
        }
        return true
    }
}

extension Components.Schemas.ConversationsInfoResponse: SlackResponse {}
