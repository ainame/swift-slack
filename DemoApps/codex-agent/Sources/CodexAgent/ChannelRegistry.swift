import Foundation
import Logging
import SlackKit

/// One source of channel identity and origin links for routing, promotion and stopping turns.
/// Code channels stay known for this process; other channels expire and failed lookups are never cached.
actor ChannelRegistry {
    enum Kind: Sendable, Equatable {
        case codeChannel(origin: MessageLink?)
        case other
    }

    struct StopScope: Sendable {
        let channel: String
        let threadTs: String?
    }

    private struct Lookup {
        let id = UUID()
        let task: Task<Kind?, Never>
    }

    private var known: [String: (kind: Kind, expiry: ContinuousClock.Instant?)] = [:]
    private var lookups: [String: Lookup] = [:]
    private let negativeLifetime: Duration
    private let logger: Logger

    init(negativeLifetime: Duration = .seconds(600), logger: Logger) {
        self.negativeLifetime = negativeLifetime
        self.logger = logger
    }

    func rememberCodeChannel(_ channel: String, origin: MessageLink?) {
        let origin = origin ?? Self.origin(in: known[channel]?.kind)
        known[channel] = (.codeChannel(origin: origin), nil)
    }

    func isCodeChannel(_ channel: String) -> Bool {
        if case .codeChannel? = known[channel]?.kind {
            true
        } else {
            false
        }
    }

    func origin(of channel: String) -> MessageLink? {
        Self.origin(in: known[channel]?.kind)
    }

    /// Resolves cached identity without looking up Slack. Unknown channels retain thread scope;
    /// this registry does not infer Code channel identity after a cold restart.
    func stopScope(channel: String, threadTs: String?) -> StopScope {
        StopScope(channel: channel, threadTs: isCodeChannel(channel) ? nil : threadTs.flatMap { $0.isEmpty ? nil : $0 })
    }

    func kind(of channel: String, client: any APIProtocol) async -> Kind? {
        if let entry = known[channel], entry.expiry.map({ ContinuousClock.now < $0 }) ?? true {
            return entry.kind
        }
        let lookup: Lookup
        if let pending = lookups[channel] {
            lookup = pending
        } else {
            lookup = Lookup(task: Task { [logger] () -> Kind? in
                do {
                    let response = try await client.conversationsInfo(body: .json(.init(channel: channel)))
                        .ok.body.json.checked("conversations.info")
                    return Self.kind(of: response.channel)
                } catch {
                    logger.warning("Failed to look up the channel", metadata: ["channel": "\(channel)", "error": "\(error)"])
                    return nil
                }
            })
            lookups[channel] = lookup
        }
        let kind = await lookup.task.value
        if lookups[channel]?.id == lookup.id {
            lookups[channel] = nil
            // Promotion or turn registration may have recorded a Code channel during the await. A stale
            // lookup must never erase that identity or its origin, and old waiters cannot clear a new lookup.
            if !isCodeChannel(channel), let kind {
                known[channel] = (kind, kind == .other ? ContinuousClock.now + negativeLifetime : nil)
            }
        }
        return isCodeChannel(channel) ? known[channel]?.kind : kind
    }

    private static func origin(in kind: Kind?) -> MessageLink? {
        if case let .codeChannel(origin)? = kind {
            origin
        } else {
            nil
        }
    }

    private static func kind(of conversation: Conversation?) -> Kind {
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
