import Logging
import SlackKit

/// Remembers promotions in this process. Slack's stable session_id also makes retries and restarts idempotent.
actor CodeChannelLifecycle {
    private var channels: [SessionKey: String] = [:]
    private var origins: [String: MessageLink] = [:]
    private var launched: Set<SessionKey> = []

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
        if origins[session.channel] != nil {
            return (session.channel, false)
        }
        try check(producer)
        let channel: String
        if let existing = channels[session] {
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
            channels[session] = id
            origins[id] = .init(channel: session.channel, ts: messageTs)
            logger.info("Created Code channel", metadata: ["origin": "\(session)", "channel": "\(id)"])
            channel = id
        }
        try check(producer)
        // These decorate an already created channel. A failed decoration must not lose the task handoff.
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
            logger.warning("Could not configure Code channel commands", metadata: ["channel": "\(channel)", "error": "\(error)"])
        }
        try check(producer)
        return (channel, launched.insert(session).inserted)
    }

    func origin(of channel: String) -> MessageLink? {
        origins[channel]
    }

    func hasOrigin(channel: String) -> Bool {
        channels.values.contains(channel)
    }

    private func check(_ producer: TurnProducer) throws {
        guard producer.reason == nil else { throw CancellationError() }
    }
}

extension Components.Schemas.AgentsConversationsCreateResponse: SlackResponse {}
extension Components.Schemas.AgentsConversationsArchiveResponse: SlackResponse {}
