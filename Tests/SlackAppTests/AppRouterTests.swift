#if Events
import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime
@testable import SlackApp
import SlackClient
import Testing

struct AppRouterTests {
    @Test func `slash command registration uses last handler`() async throws {
        actor Tracker {
            private(set) var value: String?
            func set(_ value: String) {
                self.value = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onSlashCommand("/test") { _, _ in await tracker.set("first") }
        router.onSlashCommand("/test") { _, _ in await tracker.set("second") }

        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(
            context: .request(makeRequestContext()),
            request: .slashCommand(makeSlashCommandPayload(command: "/test")),
        )

        #expect(await tracker.value == "second")
    }

    @Test func `specific event dispatch uses last typed handler`() async throws {
        actor Tracker {
            private(set) var text: String?
            func setText(_ value: String?) {
                text = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onEvent(MessageEvent.self) { _, _, _ in
            await tracker.setText("first")
        }
        router.onEvent(MessageEvent.self) { _, _, event in
            await tracker.setText(event.text)
        }

        let envelope = try makeMessageEventEnvelope(text: "hello")
        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(
            context: .event(makeEventContext()),
            request: .event(envelope),
        )

        #expect(await tracker.text == "hello")
    }

    @Test func `broad event dispatch uses last handler`() async throws {
        actor Tracker {
            private(set) var value: String?
            func set(_ value: String) {
                self.value = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onEvent { _, _ in await tracker.set("first") }
        router.onEvent { _, _ in await tracker.set("second") }

        let envelope = try makeMessageEventEnvelope(text: "hello")
        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(
            context: .event(makeEventContext()),
            request: .event(envelope),
        )

        #expect(await tracker.value == "second")
    }

    @Test func `typed event takes precedence over broad event handler`() async throws {
        actor Tracker {
            private(set) var value: String?
            func set(_ value: String) {
                self.value = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onEvent { _, _ in await tracker.set("broad") }
        router.onEvent(MessageEvent.self) { _, _, _ in await tracker.set("typed") }

        let envelope = try makeMessageEventEnvelope(text: "hello")
        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(
            context: .event(makeEventContext()),
            request: .event(envelope),
        )

        #expect(await tracker.value == "typed")
    }

    @Test func `interactive dispatch uses specific handler over broad interactive handler`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("broad") }
        router.onAction("button-id") { _, _ in await tracker.set("action") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: "modal"))

        #expect(await tracker.value == "action")
    }

    @Test func `action dispatch matches action id from message without view`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("broad") }
        router.onAction("button-id") { _, payload in
            await tracker.set(payload.blockActions.first?.actionId ?? "")
        }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: nil))

        #expect(await tracker.value == "button-id")
    }

    @Test func `action dispatch ignores other action ids`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("broad") }
        router.onAction("other-id") { _, _ in await tracker.set("action") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: nil))

        #expect(await tracker.value == "broad")
    }

    @Test func `action dispatch prefers handler with matching block id`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onAction("button-id") { _, _ in await tracker.set("action") }
        router.onAction("button-id", blockId: "block-1") { _, _ in await tracker.set("block-1") }
        router.onAction("button-id", blockId: "block-2") { _, _ in await tracker.set("block-2") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", blockId: "block-1", viewCallbackId: nil))
        #expect(await tracker.value == "block-1")

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", blockId: "block-3", viewCallbackId: nil))
        #expect(await tracker.value == "action")
    }

    @Test func `action dispatch prefers block id match across all actions`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onAction("first") { _, _ in await tracker.set("first") }
        router.onAction("second", blockId: "block-2") { _, _ in await tracker.set("second") }

        try await dispatch(router, makeBlockActionEnvelope(actions: [
            (actionId: "first", blockId: "block-1"),
            (actionId: "second", blockId: "block-2"),
        ]))

        #expect(await tracker.value == "second")
    }

    @Test func `action dispatch with block id ignores other blocks`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("broad") }
        router.onAction("button-id", blockId: "block-2") { _, _ in await tracker.set("block-2") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", blockId: "block-1", viewCallbackId: nil))

        #expect(await tracker.value == "broad")
    }

    @Test
    @available(*, deprecated)
    func `deprecated onBlockAction matches the view callback id`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("broad") }
        router.onBlockAction("modal") { _, _ in await tracker.set("callback") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: "modal"))
        #expect(await tracker.value == "callback")

        try await dispatch(router, makeBlockActionEnvelope(actionId: "modal", viewCallbackId: nil))
        #expect(await tracker.value == "broad")
    }

    @Test
    @available(*, deprecated)
    func `onAction takes precedence over deprecated onBlockAction`() async throws {
        let tracker = ValueTracker()
        let router = Router()
        router.onBlockAction("modal") { _, _ in await tracker.set("callback") }
        router.onAction("button-id") { _, _ in await tracker.set("action") }

        try await dispatch(router, makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: "modal"))
        #expect(await tracker.value == "action")

        try await dispatch(router, makeBlockActionEnvelope(actionId: "other-id", viewCallbackId: "modal"))
        #expect(await tracker.value == "callback")
    }

    @Test func `interactive dispatch uses last broad handler`() async throws {
        actor Tracker {
            private(set) var value: String?
            func set(_ value: String) {
                self.value = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onInteractive { _, _ in await tracker.set("first") }
        router.onInteractive { _, _ in await tracker.set("second") }

        let body = try makeBlockActionEnvelope(actionId: "button-id", viewCallbackId: nil)
        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(context: .request(makeRequestContext()), request: .interactive(body))

        #expect(await tracker.value == "second")
    }

    @Test func `view handlers share namespace by callback id`() async throws {
        actor Tracker {
            private(set) var value: String?
            func set(_ value: String) {
                self.value = value
            }
        }

        let tracker = Tracker()
        let router = Router()
        router.onView("modal") { _, _ in await tracker.set("view") }
        router.onViewSubmission("modal") { _, _ in await tracker.set("submission") }

        let body = try makeViewSubmissionEnvelope(callbackId: "modal")
        let fixedRouter = Router.FixedRouter(from: router)
        try await fixedRouter.dispatch(context: .request(makeRequestContext()), request: .interactive(body))

        #expect(await tracker.value == "submission")
    }
}

private func makeSlashCommandPayload(command: String) throws -> SlashCommandsPayload {
    let bodyData = try #require(
        """
        {
          "trigger_id": "trigger",
          "command": "\(command)",
          "text": "",
          "user_id": "U123",
          "user_name": "ainame",
          "team_id": "T123",
          "team_domain": "example",
          "channel_id": "C123",
          "channel_name": "general",
          "response_url": "https://hooks.slack.com/commands/T123/1/2",
          "api_app_id": "A123",
          "token": "legacy"
        }
        """.data(using: .utf8),
    )
    return try JSONDecoder().decode(SlashCommandsPayload.self, from: bodyData)
}

private func makeMessageEventEnvelope(text: String) throws -> EventsApiEnvelope<Event> {
    let eventData = try #require(
        """
        {
          "team_id": "T123",
          "api_app_id": "A123",
          "event": {
            "type": "message",
            "channel": "C123",
            "channel_type": "channel",
            "event_ts": "123",
            "team": "T123",
            "text": "\(text)",
            "ts": "123",
            "user": "U123"
          },
          "type": "event_callback",
          "event_id": "Ev123",
          "event_time": 123
        }
        """.data(using: .utf8),
    )
    return try JSONDecoder().decode(EventsApiEnvelope<Event>.self, from: eventData)
}

private actor ValueTracker {
    private(set) var value: String?
    func set(_ value: String) {
        self.value = value
    }
}

private func dispatch(_ router: Router, _ envelope: InteractiveEnvelope) async throws {
    let fixedRouter = Router.FixedRouter(from: router)
    try await fixedRouter.dispatch(context: .request(makeRequestContext()), request: .interactive(envelope))
}

private func makeBlockActionEnvelope(
    actionId: String,
    blockId: String = "block-1",
    viewCallbackId: String?,
) throws -> InteractiveEnvelope {
    try makeBlockActionEnvelope(actions: [(actionId: actionId, blockId: blockId)], viewCallbackId: viewCallbackId)
}

private func makeBlockActionEnvelope(
    actions: [(actionId: String, blockId: String)],
    viewCallbackId: String? = nil,
) throws -> InteractiveEnvelope {
    let container = if viewCallbackId == nil {
        """
        { "type": "message", "message_ts": "123.456", "channel_id": "C123", "is_ephemeral": false }
        """
    } else {
        """
        { "type": "view", "view_id": "V123" }
        """
    }
    let view = viewCallbackId.map {
        """
        "view": {
          "type": "modal",
          "callback_id": "\($0)",
          "title": { "type": "plain_text", "text": "Test" },
          "blocks": []
        },
        """
    } ?? ""
    let actionsJSON = actions.map { action in
        """
        {
          "action_id": "\(action.actionId)",
          "block_id": "\(action.blockId)",
          "text": { "type": "plain_text", "text": "Click" },
          "value": "test",
          "type": "button",
          "action_ts": "123.456"
        }
        """
    }.joined(separator: ",")
    let bodyData = try #require(
        """
        {
          "type": "block_actions",
          "user": { "id": "U123" },
          "api_app_id": "A123",
          "token": "legacy-token",
          "container": \(container),
          "trigger_id": "13345224609.738474920.8088930838d88f008e0",
          "team": { "id": "T123", "domain": "example" },
          "channel": { "id": "C123", "name": "general" },
          \(view)
          "response_url": "https://hooks.slack.com/actions/T123/1/2",
          "actions": [\(actionsJSON)],
          "state": {"values": {}}
        }
        """.data(using: .utf8),
    )
    return try JSONDecoder().decode(InteractiveEnvelope.self, from: bodyData)
}

private func makeViewSubmissionEnvelope(callbackId: String) throws -> InteractiveEnvelope {
    let bodyData = try #require(
        """
        {
          "type": "view_submission",
          "user": { "id": "U123" },
          "api_app_id": "A123",
          "token": "legacy-token",
          "trigger_id": "13345224609.738474920.8088930838d88f008e0",
          "team": { "id": "T123", "domain": "example" },
          "view": {
            "id": "V123",
            "team_id": "T123",
            "type": "modal",
            "callback_id": "\(callbackId)",
            "title": { "type": "plain_text", "text": "Test" },
            "blocks": [],
            "state": {"values": {}}
          }
        }
        """.data(using: .utf8),
    )
    return try JSONDecoder().decode(InteractiveEnvelope.self, from: bodyData)
}

private func makeEventContext() async -> SlackApp.EventContext {
    let logger = Logger(label: "test")
    let transport = MockTransport()
    let slack = Slack(transport: transport)
    let client = await slack.client

    return SlackApp.EventContext(
        client: client,
        logger: logger,
        respond: Respond(transport: transport, logger: logger),
        say: Say(client: client, logger: logger),
    )
}

private func makeRequestContext() async -> SlackApp.Context {
    let logger = Logger(label: "test")
    let transport = MockTransport()
    let slack = Slack(transport: transport)
    let client = await slack.client

    return SlackApp.Context(
        client: client,
        logger: logger,
        respond: Respond(transport: transport, logger: logger),
        say: Say(client: client, logger: logger),
        ack: Ack(
            basicHandler: {},
            viewHandler: { _, _ in },
            errorHandler: { _ in },
        ),
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
#endif
