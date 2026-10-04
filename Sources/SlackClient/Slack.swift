import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime

/// The main Slack client providing access to Slack's Web API.
///
/// `Slack` is an actor-based client that provides type-safe access to Slack's APIs through
/// code generated from OpenAPI specifications.
///
/// ## Usage
///
/// ### Basic Setup
/// ```swift
/// let slack = Slack(
///     transport: AsyncHTTPClientTransport(),
///     configuration: .init(token: "xoxb-your-bot-token")
/// )
/// ```
///
/// ### Web API Calls
/// ```swift
/// try await slack.client.chatPostMessage(
///     body: .json(.init(
///         channel: "#general",
///         text: "Hello from Swift!"
///     ))
/// )
/// ```
///
public actor Slack {
    public let client: APIProtocol
    package let transport: any ClientTransport
    package let clientConfiguration: Configuration
    var requestMiddleware: RequestMiddlware
    let formEncodingMiddleware: FormEncodingMiddleware
    package let logger: Logger

    public init(
        serverURL: URL = URL(string: "https://slack.com/api")!,
        transport: any ClientTransport,
        middlewares: [any ClientMiddleware] = [],
        logger: Logger? = nil,
        configuration: Configuration = .init(),
    ) {
        clientConfiguration = configuration
        requestMiddleware = RequestMiddlware(configuration: .init(
            token: configuration.token,
            userAgent: configuration.userAgent,
        ))
        formEncodingMiddleware = FormEncodingMiddleware()
        client = Client(
            serverURL: serverURL,
            transport: transport,
            middlewares: middlewares + [formEncodingMiddleware, requestMiddleware],
        )
        self.transport = transport
        self.logger = logger ?? Logger(label: "Slack")
    }

    public func setToken(_ value: String?) async {
        guard let value else { return }
        await requestMiddleware.setToken(value)
    }
}
