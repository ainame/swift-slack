import Foundation
import Logging
import SlackKit

/// Remembers promotions in this process. Slack's stable session_id also makes retries and restarts idempotent.
actor CodeChannelLifecycle {
    nonisolated let channels: ChannelRegistry
    private var promotions: [SessionKey: String] = [:]
    private struct Preparation {
        let id = UUID()
        let task: Task<String, any Error>
    }

    private var preparing: [SessionKey: Preparation] = [:]
    private var configured: Set<SessionKey> = []
    private var launched: Set<SessionKey> = []

    init(channels: ChannelRegistry = ChannelRegistry(logger: Logger(label: "codex-agent.channels"))) {
        self.channels = channels
    }

    func create(
        name: String,
        from session: SessionKey,
        messageTs: String,
        client: any APIProtocol,
        producer: TurnProducer,
        logger: Logger,
    ) async throws -> (channel: String, shouldLaunch: Bool) {
        // A failed conversations.info lookup must never nest a new channel inside one we created.
        if case .codeChannel = session {
            return (session.channel, false)
        }
        if await channels.isCodeChannel(session.channel) {
            return (session.channel, false)
        }
        try check(producer)
        let preparation: Preparation
        if let pending = preparing[session] {
            preparation = pending
        } else {
            preparation = Preparation(task: Task {
                try await prepare(name: name, session: session, messageTs: messageTs, client: client, producer: producer, logger: logger)
            })
            preparing[session] = preparation
        }
        defer {
            if preparing[session]?.id == preparation.id {
                preparing[session] = nil
            }
        }
        let channel = try await preparation.task.value
        try check(producer)
        return (channel, launched.insert(session).inserted)
    }

    private func prepare(
        name: String, session: SessionKey, messageTs: String, client: any APIProtocol,
        producer: TurnProducer, logger: Logger,
    ) async throws -> String {
        try check(producer)
        if configured.contains(session), let channel = promotions[session] {
            return channel
        }
        let channel: String
        if let existing = promotions[session] {
            channel = existing
        } else {
            let result = try await client.agentsConversationsCreate(body: .json(.init(
                sessionId: "swift-slack-codex:\(session)",
                name: name,
                originChannelId: session.channel,
                originMessageTs: messageTs,
            ))).ok.body.json.checked("agents.conversations.create")
            guard let id = result.channelId else {
                throw AgentToolError(description: "Slack did not return a code channel ID.")
            }
            promotions[session] = id
            await channels.rememberCodeChannel(id, origin: .init(channel: session.channel, ts: messageTs))
            logger.info("Created Code channel", metadata: ["origin": "\(session)", "channel": "\(id)"])
            channel = id
        }
        try check(producer)
        // These decorate an already created channel. A failed decoration must not lose the task handoff.
        var setupSucceeded = true
        do {
            let properties = try await client.setCodeChannelProperties(
                channelId: channel,
                properties: .init(contextBarItems: [.init(key: "agent", label: "Codex", icon: .terminal, itemType: .info)]),
            )
            if let warning = properties.warning {
                logger.warning("Code channel properties: \(warning)")
            }
        } catch {
            try check(producer)
            setupSucceeded = false
            logger.warning("Could not configure Code channel properties", metadata: ["channel": "\(channel)", "error": "\(error)"])
        }
        try check(producer)
        do {
            let commands = try await client.setCodeChannelCommands(channelId: channel, commands: [
                .init(name: "review", description: "Review the current changes"),
                .init(name: "run", description: "Run a coding task", argumentHint: "[task]"),
            ])
            if let warning = commands.warning {
                logger.warning("Code channel commands: \(warning)")
            }
        } catch {
            try check(producer)
            setupSucceeded = false
            logger.warning("Could not configure Code channel commands", metadata: ["channel": "\(channel)", "error": "\(error)"])
        }
        try check(producer)
        if setupSucceeded {
            configured.insert(session)
        }
        return channel
    }

    private func check(_ producer: TurnProducer) throws {
        try Task.checkCancellation()
        guard producer.reason == nil else { throw CancellationError() }
    }
}
