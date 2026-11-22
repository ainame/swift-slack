#if SocketMode
import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import SlackApp
import SlackBlockKit
import SlackClient
import Testing

struct SocketModeAcknowledgerTests {
    @Test func `clear acknowledgement omits the view`() async throws {
        actor Messages {
            private(set) var texts: [String] = []

            func append(_ text: String) {
                texts.append(text)
            }
        }

        let messages = Messages()
        let ack = SocketModeAcknowledger.makeAck(envelopeId: "env-1") { text in
            await messages.append(text)
        }

        try await ack(responseAction: .clear)

        let text = try #require(await messages.texts.first)
        let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary
        #expect(json == ["envelope_id": "env-1", "payload": ["response_action": "clear"]])
    }

    @Test func `options acknowledgement wraps the options in the envelope payload`() throws {
        let ack = SocketModeOptionsAck(
            envelopeId: "env-1",
            payload: OptionsResponse(
                options: [OptionObject(text: TextObject(type: .plainText, text: "Ann"), value: "U1")],
                optionGroups: nil,
            ),
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ack)) as? NSDictionary

        #expect(json == [
            "envelope_id": "env-1",
            "payload": [
                "options": [["text": ["type": "plain_text", "text": "Ann"], "value": "U1"]],
            ],
        ])
    }

    @Test func `unmatched request receives one empty acknowledgement`() async throws {
        let router = Router()
        router.onSlashCommand("/known") { _, _ in }

        #expect(try await dispatchUnknownCommand(to: router) == [#"{"envelope_id":"env-1"}"#])
    }

    @Test func `onUnmatched without acknowledgement gets an empty acknowledgement`() async throws {
        let router = Router()
        router.onUnmatched { _, _ in }

        #expect(try await dispatchUnknownCommand(to: router) == [#"{"envelope_id":"env-1"}"#])
    }

    @Test func `onUnmatched acknowledgement is not repeated`() async throws {
        let router = Router()
        router.onUnmatched { context, _ in
            guard case let .request(context) = context else { return }
            try await context.ack(errors: ["field": "Unavailable"])
        }

        let texts = try await dispatchUnknownCommand(to: router)

        #expect(texts.count == 1)
        let json = try JSONSerialization.jsonObject(with: Data(#require(texts.first).utf8)) as? NSDictionary
        #expect(json == [
            "envelope_id": "env-1",
            "payload": ["response_action": "errors", "errors": ["field": "Unavailable"]],
        ])
    }

    @Test func `matched handler acknowledgement is sent once`() async throws {
        let router = Router()
        router.onSlashCommand("/unknown") { context, _ in try await context.ack() }

        #expect(try await dispatchUnknownCommand(to: router) == [#"{"envelope_id":"env-1"}"#])
    }

    @Test func `throwing onUnmatched gets no acknowledgement`() async throws {
        struct Failure: Error {}
        let router = Router()
        router.onUnmatched { _, _ in throw Failure() }
        let messages = Messages()

        await #expect(throws: Failure.self) {
            try await dispatchUnknownCommand(to: router, messages: messages)
        }
        #expect(await messages.texts.isEmpty)
    }

    @Test func `matched handler without acknowledgement gets none`() async throws {
        let router = Router()
        router.onSlashCommand("/unknown") { _, _ in }

        #expect(try await dispatchUnknownCommand(to: router).isEmpty)
    }
}

private actor Messages {
    private(set) var texts: [String] = []

    func append(_ text: String) {
        texts.append(text)
    }
}

@discardableResult
private func dispatchUnknownCommand(to router: Router, messages: Messages = Messages()) async throws -> [String] {
    let payload = try JSONDecoder().decode(SlashCommandsPayload.self, from: Data("""
    {
      "trigger_id": "trigger", "command": "/unknown", "text": "", "user_id": "U123", "user_name": "ainame",
      "team_id": "T123", "team_domain": "example", "channel_id": "C123", "channel_name": "general",
      "response_url": "https://hooks.slack.com/commands/T123/1/2", "api_app_id": "A123"
    }
    """.utf8))
    let transport = NoopTransport()
    let client = await Slack(transport: transport).client

    try await SocketModeAcknowledger.dispatch(
        .slashCommand(payload),
        to: Router.FixedRouter(from: router),
        envelopeId: "env-1",
        write: { text in await messages.append(text) },
    ) { ack in
        SlackApp.Context(
            client: client,
            logger: .init(label: "test"),
            respond: Respond(transport: transport, logger: .init(label: "test")),
            say: Say(client: client, logger: .init(label: "test")),
            ack: ack,
        )
    }
    return await messages.texts
}

private struct NoopTransport: ClientTransport {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .ok), nil)
    }
}
#endif
