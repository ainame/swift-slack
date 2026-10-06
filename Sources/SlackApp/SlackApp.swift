import Foundation
import Logging
import OpenAPIAsyncHTTPClient
import OpenAPIRuntime
import ServiceLifecycle
import SlackClient
#if SocketMode
import NIOCore
import NIOFoundationCompat
import NIOPosix
import WSClient
#endif

public final class SlackApp {
    public typealias Configuration = Slack.Configuration

    public enum Mode: Sendable {
        #if SocketMode
        case socketMode(options: SocketModeOptions = [.autoReconnectWhenDisconnected, .recoverFromAppError], logger: Logger? = nil)
        #endif
        case http(any HTTPServerAdapter)
    }

    public struct EventContext: Sendable {
        public let client: APIProtocol
        public let logger: Logger
        public let respond: Respond
        public let say: Say
    }

    public struct Context: Sendable {
        public let client: APIProtocol
        public let logger: Logger
        public let respond: Respond
        public let say: Say
        public let ack: Ack
    }

    private let slack: Slack
    private let router: Router.FixedRouter
    private let mode: Mode

    public init(slack: Slack, router: Router, mode: Mode) {
        self.slack = slack
        self.router = .init(from: router)
        self.mode = mode
    }

    public convenience init(
        serverURL: URL = URL(string: "https://slack.com/api")!,
        configuration: Configuration = .init(),
        router: Router,
        mode: Mode,
        logger: Logger? = nil,
        middlewares: [any ClientMiddleware] = [],
    ) {
        self.init(
            slack: Slack(
                serverURL: serverURL,
                transport: AsyncHTTPClientTransport(),
                middlewares: middlewares,
                logger: logger,
                configuration: configuration,
            ),
            router: router,
            mode: mode,
        )
    }

    public func run() async throws {
        try await run(preparing: nil)
    }

    public func run(preparing: (@Sendable (Slack) async throws -> Void)? = nil) async throws {
        if let preparing {
            try await preparing(slack)
        }

        switch mode {
        #if SocketMode
        case let .socketMode(options, logger):
            try await runSocketMode(options: options, appLogger: logger)
        #endif
        case let .http(adapter):
            try await runHTTP(with: adapter)
        }
    }
}

#if SocketMode
extension SlackApp {
    private func runSocketMode(options: SocketModeOptions, appLogger: Logger?) async throws {
        while true {
            if Task.isCancelled { break }

            let url = try await slack.openSocketModeConnection()
            try await startSocketMode(with: url, options: options, appLogger: appLogger)

            if !options.contains(.autoReconnectWhenDisconnected) { break }
        }
    }

    private func startSocketMode(with url: String, options: SocketModeOptions, appLogger: Logger?) async throws {
        let router = router
        let client = await slack.client
        let transport = await slack.transport
        let logger = await slack.logger
        let runtimeLogger = appLogger ?? logger

        let ws = WebSocketClient(url: url, logger: logger) { inbound, outbound, context in
            context.logger.info("SocketMode client connected")

            try await withThrowingDiscardingTaskGroup { group in
                for try await frame in inbound {
                    guard frame.opcode == .text else { continue }

                    let envelope = await Self.decodeSocketModeFrame(frame.data, logger: logger) { envelopeId in
                        try await SocketModeAcknowledger.sendBasicAck(envelopeId: envelopeId, writer: outbound)
                    }
                    guard let envelope else { continue }

                    let request = Self.request(from: envelope)
                    group.addTask {
                        do {
                            switch request {
                            case .event:
                                try await SocketModeAcknowledger.sendBasicAck(
                                    envelopeId: envelope.envelopeId,
                                    writer: outbound,
                                )
                                let context = EventContext(
                                    client: client,
                                    logger: runtimeLogger,
                                    respond: Respond(transport: transport, logger: logger),
                                    say: Say(client: client, logger: logger),
                                )
                                try await router.dispatch(context: .event(context), request: request)
                            case .interactive, .slashCommand:
                                let context = Context(
                                    client: client,
                                    logger: runtimeLogger,
                                    respond: Respond(transport: transport, logger: logger),
                                    say: Say(client: client, logger: logger),
                                    ack: SocketModeAcknowledger.makeAck(
                                        envelopeId: envelope.envelopeId,
                                        writer: outbound,
                                    ),
                                )
                                let matched = try await router.dispatch(context: .request(context), request: request)
                                if !matched {
                                    // The router has logged the unmatched request. Match the HTTP mode, which
                                    // acknowledges requests that no handler matched.
                                    try await SocketModeAcknowledger.sendBasicAck(
                                        envelopeId: envelope.envelopeId,
                                        writer: outbound,
                                    )
                                }
                            case let .unsupported(type):
                                runtimeLogger.warning("Ignoring unsupported Socket Mode envelope type: \(type)")
                                try await SocketModeAcknowledger.sendBasicAck(
                                    envelopeId: envelope.envelopeId,
                                    writer: outbound,
                                )
                            }
                        } catch {
                            runtimeLogger.error("App Level Error: \(error)")
                            if !options.contains(.recoverFromAppError) {
                                throw error
                            }
                        }
                    }
                }
            }

            context.logger.info("SocketMode client disconnected")
        }

        do {
            try await ws.run()
        } catch {
            // Ignore error when we can/should reconnect
            guard options.contains(.autoReconnectWhenDisconnected),
                  Self.shouldReconnectSocketMode(after: error) else {
                throw error
            }

            logger.warning("SocketMode client timed out while reading; reconnecting")
        }
    }

    private static func request(from envelope: SocketModeMessageEnvelope) -> Request {
        switch envelope.payload {
        case let .interactive(payload):
            .interactive(payload)
        case let .slashCommands(payload):
            .slashCommand(payload)
        #if Events
        case let .eventsApi(payload):
            .event(payload)
        #endif
        case let .unsupported(type):
            .unsupported(type)
        }
    }

    static func shouldReconnectSocketMode(after error: any Error) -> Bool {
        guard let ioError = error as? IOError else {
            return false
        }
        // A read timeout means the current Socket Mode connection stopped producing frames,
        // so reconnecting is equivalent to recovering from an unexpected disconnect.
        return ioError.errnoCode == ETIMEDOUT
    }
}
#endif

extension SlackApp {
    private func runHTTP(with adapter: any HTTPServerAdapter) async throws {
        let handler = AppHTTPHandler(slack: slack, router: router)
        try await adapter.run(handler: handler.handle)
    }
}

#if SocketMode
extension SlackApp {
    /// Decodes one Socket Mode text frame and returns the envelope to dispatch, if any.
    ///
    /// A frame that fails to decode is logged and skipped instead of thrown, because a thrown error
    /// closes the WebSocket connection and stops the app. Acknowledgement matches HTTP mode: an
    /// `events_api` envelope whose `envelope_id` can still be read is acknowledged through `sendBasicAck`,
    /// so Slack does not retry it. Interactive requests and slash commands are left unacknowledged, so
    /// Slack shows the user an error instead of treating the request as handled, which would close a
    /// submitted modal. `hello` and `disconnect` frames are only logged, so failing to decode them changes
    /// nothing. A failed acknowledgement is logged; if the connection is broken, the frame loop ends on
    /// its own.
    static func decodeSocketModeFrame(
        _ buffer: ByteBuffer,
        logger: Logger,
        sendBasicAck: (String) async throws -> Void,
    ) async -> SocketModeMessageEnvelope? {
        let message: SocketModeMessage
        do {
            message = try JSONDecoder().decode(SocketModeMessage.self, from: buffer)
        } catch {
            let header = try? JSONDecoder().decode(SocketModeEnvelopeHeader.self, from: buffer)
            logger.error(
                "Parsing Socket Mode message failed (envelope_id: \(header?.envelopeId ?? "none"), type: \(header?._type ?? "unknown")): \(error)",
            )
            logger.debug("Socket Mode message that failed to parse: \(String(buffer: buffer))")

            guard let header, let envelopeId = header.envelopeId else { return nil }
            guard header._type == "events_api" else {
                logger.warning("Not acknowledging Socket Mode envelope \(envelopeId) that failed to decode; Slack reports the failure")
                return nil
            }
            do {
                try await sendBasicAck(envelopeId)
            } catch {
                logger.error("Acknowledging Socket Mode envelope \(envelopeId) failed: \(error)")
            }
            return nil
        }

        switch message.body {
        case let .hello(hello):
            logger.info("\(hello)")
            return nil
        case let .disconnect(disconnect):
            logger.info("\(disconnect)")
            return nil
        case let .message(envelope):
            return envelope
        }
    }
}

/// The fields of a Socket Mode message used to log and acknowledge it when it fails to decode.
private struct SocketModeEnvelopeHeader: Decodable {
    let envelopeId: String?
    let _type: String?

    private enum CodingKeys: String, CodingKey {
        case envelopeId = "envelope_id"
        case _type = "type"
    }
}
#endif

extension SlackApp: Service {}
