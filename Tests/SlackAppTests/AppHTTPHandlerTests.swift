import Crypto
import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime
@testable import SlackApp
import SlackClient
import Testing

struct AppHTTPHandlerTests {
    @Test func `app can be created from configuration`() {
        let app = SlackApp(
            configuration: .init(token: "xoxb-test", signingSecret: "secret"),
            router: Router(),
            mode: .http(NoopAdapter()),
        )

        withExtendedLifetime(app) {}
    }

    @Test func `rejects invalid signature`() async throws {
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: Router())
        let timestamp = currentTimestamp()
        let (response, responseBody) = try await app.handle(
            HTTPRequest(
                method: .post,
                scheme: "https",
                authority: "example.com",
                path: "/slack/events",
                headerFields: HTTPFields([
                    HTTPField(name: .contentType, value: "application/json"),
                    HTTPField(name: #require(HTTPField.Name("x-slack-request-timestamp")), value: timestamp),
                    HTTPField(name: #require(HTTPField.Name("x-slack-signature")), value: "v0=bad"),
                ]),
            ),
            body: Data(#"{"type":"url_verification","challenge":"abc"}"#.utf8),
        )

        #expect(response.status == .unauthorized)
        #expect(responseBody == nil)
    }

    @Test func `url verification returns challenge`() async throws {
        let body = Data(#"{"type":"url_verification","challenge":"abc"}"#.utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: Router())

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        let returnedBody = try #require(responseBody)
        #expect(String(decoding: returnedBody, as: UTF8.self).contains(#""challenge":"abc""#))
    }

    @Test func `app rate limited returns OK`() async throws {
        let body = Data(#"{"type":"app_rate_limited","team_id":"T123","minute_rate_limited":1518467820,"api_app_id":"A123"}"#.utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: Router())

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
    }

    @Test func `malformed JSON returns OK`() async throws {
        let body = Data(#"{"#.utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: Router())

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
    }

    @Test func `malformed event callback returns OK`() async throws {
        let body = Data(#"{"type":"event_callback","team_id":"T123"}"#.utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: Router())

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
    }

    @Test func `event returns after handler completes`() async throws {
        actor Tracker {
            private(set) var processed = false

            func markProcessed() {
                processed = true
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onEvent(MessageEvent.self) { _, _, _ in
            try? await Task.sleep(for: .milliseconds(200))
            await tracker.markProcessed()
        }

        let body = Data(
            #"{"team_id":"T123","api_app_id":"A123","event":{"type":"message","channel":"C123","channel_type":"channel","event_ts":"123","team":"T123","text":"hello","ts":"123","user":"U123"},"type":"event_callback","event_id":"Ev123","event_time":123}"#
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let started = ContinuousClock.now
        let (response, responseBody) = try await app.handle(request.0, body: request.1)
        let elapsed = started.duration(to: .now)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(elapsed >= .milliseconds(200))
        #expect(await tracker.processed)
    }

    @Test func `interactive returns after handler completes`() async throws {
        actor Tracker {
            private(set) var processed = false

            func markProcessed() {
                processed = true
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onSlashCommand("/echo") { context, _ in
            try await context.ack()
            try? await Task.sleep(for: .milliseconds(200))
            await tracker.markProcessed()
        }

        let body = Data(
            "command=%2Fecho&text=hello+world&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2F123%2F456&trigger_id=trigger&user_id=U123&user_name=tester&channel_id=C123&channel_name=general&team_id=T123&team_domain=example&is_enterprise_install=false&api_app_id=A123"
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let started = ContinuousClock.now
        let (response, responseBody) = try await app.handle(request.0, body: request.1)
        let elapsed = started.duration(to: .now)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(elapsed >= .milliseconds(200))
        #expect(await tracker.processed)
    }

    @Test func `event dispatches handler without ack`() async throws {
        actor Tracker {
            private(set) var text: String?

            func setText(_ value: String?) {
                text = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onEvent(MessageEvent.self) { _, _, event in
            await tracker.setText(event.text)
        }

        let body = Data(
            #"{"team_id":"T123","api_app_id":"A123","event":{"type":"message","channel":"C123","channel_type":"channel","event_ts":"123","team":"T123","text":"hello","ts":"123","user":"U123"},"type":"event_callback","event_id":"Ev123","event_time":123}"#
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/json",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)
        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(await tracker.text == "hello")
    }

    @Test func `unmatched slash command returns OK`() async throws {
        let body = Data(
            "command=%2Funknown&text=hello+world&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2F123%2F456&trigger_id=trigger&user_id=U123&user_name=tester&channel_id=C123&channel_name=general&team_id=T123&team_domain=example&is_enterprise_install=false&api_app_id=A123"
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let logs = LogRecorder()
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret", logger: logs.makeLogger()), router: Router())

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(await logs.warnings() == [#"No handler matched slash command "/unknown""#])
    }

    @Test func `message button dispatches action handler by action id`() async throws {
        actor Tracker {
            private(set) var actionId: String?

            func setActionId(_ value: String?) {
                actionId = value
            }
        }

        let json = """
        {
          "type": "block_actions",
          "user": { "id": "U123" },
          "api_app_id": "A123",
          "container": { "type": "message", "message_ts": "123.456", "channel_id": "C123", "is_ephemeral": false },
          "trigger_id": "13345224609.738474920.8088930838d88f008e0",
          "team": { "id": "T123", "domain": "example" },
          "channel": { "id": "C123", "name": "general" },
          "response_url": "https://hooks.slack.com/actions/T123/1/2",
          "actions": [{
            "type": "button",
            "action_id": "approve",
            "block_id": "request",
            "text": { "type": "plain_text", "text": "Approve" },
            "value": "1",
            "action_ts": "123.456"
          }]
        }
        """
        let encodedPayload = try #require(json.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: Data("payload=\(encodedPayload)".utf8),
            timestamp: timestamp,
        )
        let tracker = Tracker()
        let router = Router()
        router.onAction("approve") { context, payload in
            try await context.ack()
            await tracker.setActionId(payload.blockActions.first?.actionId)
        }
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(await tracker.actionId == "approve")
    }

    @Test func `unmatched interactive returns OK`() async throws {
        let body = Data(
            "payload=%7B%22type%22%3A%22block_actions%22%2C%22user%22%3A%7B%22id%22%3A%22U123%22%7D%2C%22api_app_id%22%3A%22A123%22%2C%22token%22%3A%22legacy-token%22%2C%22container%22%3A%7B%22type%22%3A%22message%22%2C%22message_ts%22%3A%22123.456%22%2C%22channel_id%22%3A%22C123%22%2C%22is_ephemeral%22%3Afalse%7D%2C%22trigger_id%22%3A%2213345224609.738474920.8088930838d88f008e0%22%2C%22team%22%3A%7B%22id%22%3A%22T123%22%2C%22domain%22%3A%22example%22%7D%2C%22channel%22%3A%7B%22id%22%3A%22C123%22%2C%22name%22%3A%22general%22%7D%2C%22view%22%3A%7B%22type%22%3A%22modal%22%2C%22callback_id%22%3A%22other-id%22%2C%22title%22%3A%7B%22type%22%3A%22plain_text%22%2C%22text%22%3A%22Test%22%7D%2C%22blocks%22%3A%5B%5D%7D%2C%22response_url%22%3A%22https%3A%2F%2Fhooks.slack.com%2Factions%2FT123%2F1%2F2%22%2C%22actions%22%3A%5B%7B%22action_id%22%3A%22button-id%22%2C%22block_id%22%3A%22block-1%22%2C%22text%22%3A%7B%22type%22%3A%22plain_text%22%2C%22text%22%3A%22Click%22%7D%2C%22value%22%3A%22test%22%2C%22type%22%3A%22button%22%2C%22action_ts%22%3A%22123.456%22%7D%5D%2C%22callback_id%22%3A%22other-id%22%7D"
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let router = Router()
        router.onAction("other-action-id") { context, _ in
            try await context.ack()
        }
        let logs = LogRecorder()
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret", logger: logs.makeLogger()), router: router)

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
        #expect(await logs.warnings() == [#"No handler matched block_actions with action_id "button-id" and block_id "block-1""#])
    }

    @Test func `view submission is acknowledged by its handler when a closed handler shares the callback id`() async throws {
        actor Tracker {
            private(set) var submitted = false

            func markSubmitted() {
                submitted = true
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onViewSubmission("feedback_modal") { context, _ in
            try await context.ack()
            await tracker.markSubmitted()
        }
        router.onViewClosed("feedback_modal") { context, _ in
            try await context.ack()
        }

        let payload = """
        {"type":"view_submission","user":{"id":"U123"},"api_app_id":"A123","token":"legacy-token","trigger_id":"trigger","team":{"id":"T123","domain":"example"},"view":{"id":"V123","team_id":"T123","type":"modal","callback_id":"feedback_modal","title":{"type":"plain_text","text":"Test"},"blocks":[],"state":{"values":{}}}}
        """
        let encodedPayload = try #require(payload.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let body = Data("payload=\(encodedPayload)".utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let (response, _) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(await tracker.submitted)
    }

    @Test func `view closed without a closed handler returns OK`() async throws {
        let router = Router()
        router.onViewSubmission("feedback_modal") { context, _ in
            try await context.ack()
        }

        let payload = """
        {"type":"view_closed","user":{"id":"U123"},"api_app_id":"A123","token":"legacy-token","team":{"id":"T123","domain":"example"},"is_cleared":false,"view":{"id":"V123","team_id":"T123","type":"modal","callback_id":"feedback_modal","notify_on_close":true,"title":{"type":"plain_text","text":"Test"},"blocks":[],"state":{"values":{}}}}
        """
        let encodedPayload = try #require(payload.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let body = Data("payload=\(encodedPayload)".utf8)
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let (response, responseBody) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(responseBody == nil)
    }

    @Test func `matched slash command without ack returns internal server error`() async throws {
        let router = Router()
        router.onSlashCommand("/echo") { _, _ in }

        let body = Data(
            "command=%2Fecho&text=hello+world&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2F123%2F456&trigger_id=trigger&user_id=U123&user_name=tester&channel_id=C123&channel_name=general&team_id=T123&team_domain=example&is_enterprise_install=false&api_app_id=A123"
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let (response, _) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .internalServerError)
    }

    @Test func `slash command dispatches handler`() async throws {
        actor Tracker {
            private(set) var text: String?

            func setText(_ value: String) {
                text = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onSlashCommand("/echo") { context, payload in
            await tracker.setText(payload.text)
            try await context.ack()
        }

        let body = Data(
            "command=%2Fecho&text=hello+world&response_url=https%3A%2F%2Fhooks.slack.com%2Fcommands%2F123%2F456&trigger_id=trigger&user_id=U123&user_name=tester&channel_id=C123&channel_name=general&team_id=T123&team_domain=example&is_enterprise_install=false&api_app_id=A123"
                .utf8,
        )
        let timestamp = currentTimestamp()
        let request = signedRequest(
            secret: "secret",
            method: .post,
            path: "/slack/events",
            contentType: "application/x-www-form-urlencoded",
            body: body,
            timestamp: timestamp,
        )
        let app = AppHTTPHandler(slack: makeSlack(signingSecret: "secret"), router: router)

        let (response, _) = try await app.handle(request.0, body: request.1)

        #expect(response.status == .ok)
        #expect(await tracker.text == "hello world")
    }
}

private func currentTimestamp() -> String {
    String(Int(Date().timeIntervalSince1970))
}

private func makeSlack(signingSecret: String, logger: Logger? = nil) -> Slack {
    Slack(
        transport: MockTransport(),
        logger: logger,
        configuration: .init(token: "xoxb-test", signingSecret: signingSecret),
    )
}

private func signedRequest(
    secret: String,
    method: HTTPRequest.Method,
    path: String,
    contentType: String,
    body: Data,
    timestamp: String,
) -> (HTTPRequest, Data) {
    let base = "v0:\(timestamp):" + String(decoding: body, as: UTF8.self)
    let key = SymmetricKey(data: Data(secret.utf8))
    let digest = HMAC<SHA256>.authenticationCode(for: Data(base.utf8), using: key)
    let signature = "v0=" + digest.map { String(format: "%02x", $0) }.joined()

    return (
        HTTPRequest(
            method: method,
            scheme: "https",
            authority: "example.com",
            path: path,
            headerFields: HTTPFields([
                HTTPField(name: .contentType, value: contentType),
                HTTPField(name: HTTPField.Name("x-slack-request-timestamp")!, value: timestamp),
                HTTPField(name: HTTPField.Name("x-slack-signature")!, value: signature),
            ]),
        ),
        body,
    )
}

private struct MockTransport: ClientTransport {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .ok), nil)
    }
}

private struct NoopAdapter: HTTPServerAdapter {
    func run(
        handler _: @escaping HTTPServerHandler,
    ) async throws {}
}
