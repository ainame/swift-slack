#if SocketMode
import Logging
import NIOCore
@testable import SlackApp
import Testing

struct SocketModeFrameDecodingTests {
    private let logger = Logger(label: "test")

    @Test func `undecodable Events API envelope is acknowledged and skipped`() async {
        // A message event whose blocks include a malformed block (unknown block types decode as .unknown).
        let json = """
        {
          "envelope_id": "env-1",
          "type": "events_api",
          "accepts_response_payload": false,
          "payload": {
            "team_id": "T123",
            "api_app_id": "A123",
            "type": "event_callback",
            "event_id": "Ev123",
            "event_time": 1700000000,
            "event": {
              "type": "message",
              "channel": "C123",
              "user": "U123",
              "text": "hello",
              "ts": "1.2",
              "blocks": [{ "type": "section", "block_id": "b1", "text": "not a text object" }]
            }
          }
        }
        """
        let acks = AckRecorder()

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) {
            await acks.record($0)
        }

        #expect(envelope == nil)
        #expect(await acks.envelopeIds == ["env-1"])
    }

    @Test(arguments: [
        // A view submission whose view includes a malformed block (unknown block types decode as .unknown).
        """
        {
          "envelope_id": "env-1",
          "type": "interactive",
          "accepts_response_payload": true,
          "payload": {
            "type": "view_submission",
            "user": { "id": "U123" },
            "team": { "id": "T123" },
            "view": {
              "id": "V123",
              "type": "modal",
              "title": { "type": "plain_text", "text": "Preferences" },
              "blocks": [{ "type": "section", "text": "not a text object" }]
            }
          }
        }
        """,
        // A slash command without the required `command` field.
        """
        {
          "envelope_id": "env-1",
          "type": "slash_commands",
          "accepts_response_payload": true,
          "payload": { "text": "hello" }
        }
        """,
    ])
    func `undecodable request envelope is skipped without acknowledgement`(json: String) async {
        let acks = AckRecorder()

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) {
            await acks.record($0)
        }

        #expect(envelope == nil)
        #expect(await acks.envelopeIds.isEmpty)
    }

    @Test func `failed acknowledgement is logged instead of thrown`() async {
        let json = #"{ "envelope_id": "env-1", "type": "events_api", "payload": {} }"#

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) { _ in
            throw AckFailure()
        }

        #expect(envelope == nil)
    }

    @Test(arguments: [
        "not json",
        #"{ "type": "hello" }"#,
        #"{ "type": "disconnect", "reason": "warning" }"#,
        #"{ "type": "slash_commands", "payload": {} }"#,
    ])
    func `undecodable frame without envelope ID is skipped without acknowledgement`(json: String) async {
        let acks = AckRecorder()

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) {
            await acks.record($0)
        }

        #expect(envelope == nil)
        #expect(await acks.envelopeIds.isEmpty)
    }

    @Test func `hello frame is skipped without acknowledgement`() async {
        let json = """
        {
          "type": "hello",
          "num_connections": 1,
          "debug_info": { "host": "applink-1", "build_number": 1, "approximate_connection_time": 18060 },
          "connection_info": { "app_id": "A123" }
        }
        """
        let acks = AckRecorder()

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) {
            await acks.record($0)
        }

        #expect(envelope == nil)
        #expect(await acks.envelopeIds.isEmpty)
    }

    @Test func `decodable envelope is returned for dispatch without acknowledgement`() async throws {
        let json = """
        {
          "envelope_id": "env-2",
          "type": "slash_commands",
          "accepts_response_payload": true,
          "payload": {
            "command": "/echo",
            "text": "hello",
            "response_url": "https://hooks.slack.com/commands/T123/1/abc",
            "trigger_id": "1.2.abc",
            "user_id": "U123",
            "user_name": "user",
            "channel_id": "C123",
            "channel_name": "general",
            "team_id": "T123",
            "team_domain": "example",
            "is_enterprise_install": "false",
            "api_app_id": "A123"
          }
        }
        """
        let acks = AckRecorder()

        let envelope = await SlackApp.decodeSocketModeFrame(ByteBuffer(string: json), logger: logger) {
            await acks.record($0)
        }

        let decoded = try #require(envelope)
        #expect(decoded.envelopeId == "env-2")
        guard case let .slashCommands(payload) = decoded.payload else {
            Issue.record("Expected a slash command payload, got \(decoded.payload)")
            return
        }
        #expect(payload.command == "/echo")
        #expect(await acks.envelopeIds.isEmpty)
    }
}

private struct AckFailure: Error {}

private actor AckRecorder {
    private(set) var envelopeIds: [String] = []

    func record(_ envelopeId: String) {
        envelopeIds.append(envelopeId)
    }
}
#endif
