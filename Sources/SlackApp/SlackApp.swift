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

                    let message = try Self.parseSocketModeMessage(frame.data, logger: logger)
                    guard case let .message(envelope) = message.body else { continue }

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
                                    // Match the HTTP mode, which acknowledges requests that no handler matched.
                                    runtimeLogger.info("No handler matched Socket Mode request; sending an empty acknowledgement")
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
    private static func parseSocketModeMessage(_ buffer: ByteBuffer, logger: Logger) throws -> SocketModeMessage {
        do {
            let messageType = try JSONDecoder().decode(SocketModeMessage.self, from: buffer)
            switch messageType.body {
            case let .hello(message):
                logger.info("\(message)")
            case let .disconnect(message):
                logger.info("\(message)")
            case .message:
                break
            }
            return messageType
        } catch {
            let message = String(buffer: buffer)
            logger.error("Parsing message failed: \(error) /// \(message)")
            throw error
        }
    }
}
#endif

extension SlackApp: Service {}
