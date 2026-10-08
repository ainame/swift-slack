import Foundation
import HTTPTypes
import SlackBlockKit
import SlackClient

private actor HTTPAcknowledgmentState {
    private enum StoredResponse {
        case empty
        case json(Foundation.Data)
    }

    private var storedResponse: StoredResponse?

    func storeEmptyIfNeeded() throws {
        try store(.empty)
    }

    func storeJSON(_ data: Foundation.Data) throws {
        try store(.json(data))
    }

    private func store(_ response: StoredResponse) throws {
        guard storedResponse == nil else {
            throw Slack.Error.genericError("ack() already called")
        }
        storedResponse = response
    }

    func response() -> (response: HTTPResponse, body: Foundation.Data?)? {
        switch storedResponse {
        case .empty:
            (HTTPResponse(status: .ok), nil)
        case let .json(data):
            (
                HTTPResponse(
                    status: .ok,
                    headerFields: HTTPFields([HTTPField(name: .contentType, value: "application/json")]),
                ),
                data,
            )
        case nil:
            nil
        }
    }
}

struct AppHTTPHandler {
    private static let contentTypeField = HTTPField.Name.contentType

    private struct JSONEnvelope: Decodable {
        let type: String
        let challenge: String?
    }

    private struct ViewAckPayload: Encodable {
        let responseAction: String
        let view: View?

        private enum CodingKeys: String, CodingKey {
            case responseAction = "response_action"
            case view
        }
    }

    private struct ErrorAckPayload: Encodable {
        let responseAction: String
        let errors: [String: String]

        private enum CodingKeys: String, CodingKey {
            case responseAction = "response_action"
            case errors
        }
    }

    private let slack: Slack
    private let router: Router.FixedRouter
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    init(slack: Slack, router: Router.FixedRouter) {
        self.slack = slack
        self.router = router
    }

    init(slack: Slack, router: Router) {
        self.init(slack: slack, router: .init(from: router))
    }

    func handle(_ request: HTTPRequest, body: Foundation.Data) async throws -> (response: HTTPResponse, body: Foundation.Data?) {
        let logger = await slack.logger

        let configuration = await slack.clientConfiguration
        let verifier = HTTPRequestVerifier(signingSecret: configuration.signingSecret ?? "")

        do {
            try verifier.verify(headerFields: request.headerFields, body: body)
        } catch {
            logger.warning("Rejected Slack HTTP request due to failed signature verification")
            return (HTTPResponse(status: .unauthorized), nil)
        }

        if let response = try await handleJSONRequestIfNeeded(request, body: body, configuration: configuration) {
            return response
        }

        if let response = try await handleFormRequestIfNeeded(request, body: body) {
            return response
        }

        return (HTTPResponse(status: .unsupportedMediaType), nil)
    }

    private func handleJSONRequestIfNeeded(
        _ request: HTTPRequest,
        body: Foundation.Data,
        configuration _: Slack.Configuration,
    ) async throws -> (response: HTTPResponse, body: Foundation.Data?)? {
        guard contentType(of: request.headerFields)?.starts(with: "application/json") == true else {
            return nil
        }

        let logger = await slack.logger
        let envelope: JSONEnvelope
        do {
            envelope = try jsonDecoder.decode(JSONEnvelope.self, from: body)
        } catch {
            logger.warning("Ignoring malformed Slack JSON request after successful signature verification")
            return (HTTPResponse(status: .ok), nil)
        }

        switch envelope.type {
        case "url_verification":
            let data = try jsonEncoder.encode(["challenge": envelope.challenge ?? ""])
            return (
                HTTPResponse(
                    status: .ok,
                    headerFields: HTTPFields([HTTPField(name: .contentType, value: "application/json")]),
                ),
                data,
            )
        case "event_callback":
            #if Events
            do {
                let payload = try jsonDecoder.decode(EventsApiEnvelope<Event>.self, from: body)
                return try await dispatchEvent(.event(payload))
            } catch {
                logger.warning("Ignoring malformed Slack event_callback request after successful signature verification")
                return (HTTPResponse(status: .ok), nil)
            }
            #else
            return (HTTPResponse(status: .notImplemented), nil)
            #endif
        case "app_rate_limited":
            return (HTTPResponse(status: .ok), nil)
        default:
            logger.warning("Ignoring unsupported Slack JSON request type: \(envelope.type)")
            return (HTTPResponse(status: .ok), nil)
        }
    }

    private func handleFormRequestIfNeeded(
        _ request: HTTPRequest,
        body: Foundation.Data,
    ) async throws -> (response: HTTPResponse, body: Foundation.Data?)? {
        guard contentType(of: request.headerFields)?.starts(with: "application/x-www-form-urlencoded") == true else {
            return nil
        }

        let values = Self.decodeFormBody(body)

        if let payloadString = values["payload"] {
            let payload = try jsonDecoder.decode(InteractiveEnvelope.self, from: Foundation.Data(payloadString.utf8))
            return try await dispatchRequest(.interactive(payload))
        }

        let json = try JSONSerialization.data(withJSONObject: values, options: [])
        let payload = try jsonDecoder.decode(SlashCommandsPayload.self, from: json)
        return try await dispatchRequest(.slashCommand(payload))
    }

    private func dispatchEvent(_ request: Request) async throws -> (response: HTTPResponse, body: Foundation.Data?) {
        let client = await slack.client
        let transport = await slack.transport
        let logger = await slack.logger
        let respond = Respond(transport: transport, logger: logger)
        let say = Say(client: client, logger: logger)

        let context = SlackApp.EventContext(
            client: client,
            logger: logger,
            respond: respond,
            say: say,
        )
        do {
            _ = try await router.dispatch(context: .event(context), request: request)
        } catch {
            logger.error("Failed to process Slack event request: \(String(describing: error))")
        }
        return (HTTPResponse(status: .ok), nil)
    }

    private func dispatchRequest(_ request: Request) async throws -> (response: HTTPResponse, body: Foundation.Data?) {
        let client = await slack.client
        let transport = await slack.transport
        let logger = await slack.logger
        let respond = Respond(transport: transport, logger: logger)
        let say = Say(client: client, logger: logger)
        let state = HTTPAcknowledgmentState()
        let context = SlackApp.Context(
            client: client,
            logger: logger,
            respond: respond,
            say: say,
            ack: Ack(
                basicHandler: {
                    try await state.storeEmptyIfNeeded()
                },
                viewHandler: { responseAction, view in
                    let data = try jsonEncoder.encode(ViewAckPayload(responseAction: responseAction, view: view))
                    try await state.storeJSON(data)
                },
                errorHandler: { errors in
                    let data = try jsonEncoder.encode(ErrorAckPayload(responseAction: "errors", errors: errors))
                    try await state.storeJSON(data)
                },
                optionsHandler: { response in
                    try await state.storeJSON(jsonEncoder.encode(response))
                },
            ),
        )
        do {
            let matched = try await router.dispatch(context: .request(context), request: request)
            if let response = await state.response() {
                return response
            }
            if !matched {
                return (HTTPResponse(status: .ok), nil)
            }
            return (HTTPResponse(status: .internalServerError), nil)
        } catch {
            logger.error("Failed to process Slack HTTP request: \(String(describing: error))")
            if let response = await state.response() {
                return response
            }
            return (HTTPResponse(status: .internalServerError), nil)
        }
    }

    private func contentType(of headers: HTTPFields) -> String? {
        headers[values: Self.contentTypeField].first
    }

    private static func decodeFormBody(_ body: Foundation.Data) -> [String: String] {
        let query = String(decoding: body, as: UTF8.self)
        var result: [String: String] = [:]
        for part in query.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = pair.first?.removingPercentEncoding else { continue }
            let value = pair.count == 2 ? (pair[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? pair[1]) : ""
            result[key] = value
        }
        return result
    }
}
