import Foundation
import Logging
import SlackKit
import Synchronization

/// One source of channel identity and origin links for routing, promotion and stopping turns.
///
/// Code channels stay known for this process; other channels expire and failed lookups are never cached.
/// Synchronous access lets a responder record a Code channel and reserve its turn before its first await.
final class ChannelRegistry: Sendable {
    enum Kind: Sendable, Equatable {
        case codeChannel(origin: MessageLink?)
        case other
    }

    struct StopScope: Sendable {
        let channel: String
        let threadTs: String?
    }

    private struct Lookup: Sendable {
        let id = UUID()
        let task: Task<Kind?, Never>
    }

    private struct State {
        var known: [String: (kind: Kind, expiry: ContinuousClock.Instant?)] = [:]
        var lookups: [String: Lookup] = [:]
    }

    private enum Resolution {
        case cached(Kind)
        case lookup(Lookup)
    }

    private let state = Mutex(State())
    private let negativeLifetime: Duration
    private let logger: Logger

    init(negativeLifetime: Duration = .seconds(600), logger: Logger) {
        self.negativeLifetime = negativeLifetime
        self.logger = logger
    }

    func rememberCodeChannel(_ channel: String, origin: MessageLink?) {
        state.withLock { state in
            let origin = origin ?? Self.origin(in: state.known[channel]?.kind)
            state.known[channel] = (.codeChannel(origin: origin), nil)
        }
    }

    func isCodeChannel(_ channel: String) -> Bool {
        state.withLock { state in
            if case .codeChannel? = state.known[channel]?.kind {
                true
            } else {
                false
            }
        }
    }

    func origin(of channel: String) -> MessageLink? {
        state.withLock { Self.origin(in: $0.known[channel]?.kind) }
    }

    /// A stop's scope is resolved once, without awaiting Slack. Unknown channels retain thread scope;
    /// this registry does not infer Code channel identity after a cold restart.
    func stopScope(channel: String, threadTs: String?) -> StopScope {
        state.withLock { state in
            let threadTs: String? = if case .codeChannel? = state.known[channel]?.kind {
                nil
            } else {
                threadTs.flatMap { $0.isEmpty ? nil : $0 }
            }
            return StopScope(channel: channel, threadTs: threadTs)
        }
    }

    func kind(of channel: String, client: any APIProtocol) async -> Kind? {
        let resolution = state.withLock { state -> Resolution in
            if let entry = state.known[channel], entry.expiry.map({ ContinuousClock.now < $0 }) ?? true {
                return .cached(entry.kind)
            }
            if let lookup = state.lookups[channel] {
                return .lookup(lookup)
            }
            let lookup = Lookup(task: Task { [logger] () -> Kind? in
                do {
                    let response = try await client.conversationsInfo(body: .json(.init(channel: channel)))
                        .ok.body.json.checked("conversations.info")
                    return Self.kind(of: response.channel)
                } catch {
                    logger.warning("Failed to look up the channel", metadata: ["channel": "\(channel)", "error": "\(error)"])
                    return nil
                }
            })
            state.lookups[channel] = lookup
            return .lookup(lookup)
        }
        switch resolution {
        case let .cached(kind):
            return kind
        case let .lookup(lookup):
            let kind = await lookup.task.value
            return state.withLock { state in
                if state.lookups[channel]?.id == lookup.id {
                    state.lookups[channel] = nil
                    // Promotion or turn registration may have recorded a Code channel while Slack was
                    // answering. A stale lookup must never erase that identity or its origin.
                    if case .codeChannel? = state.known[channel]?.kind {
                        return state.known[channel]?.kind
                    }
                    if let kind {
                        state.known[channel] = (kind, kind == .other ? ContinuousClock.now + negativeLifetime : nil)
                    }
                }
                if case .codeChannel? = state.known[channel]?.kind {
                    return state.known[channel]?.kind
                }
                return kind
            }
        }
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
