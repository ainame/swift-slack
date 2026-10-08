import Foundation
import Logging
import OpenAPIRuntime
import SlackClient

public enum DispatchContext: Sendable {
    case request(SlackApp.Context)
    #if Events
    case event(SlackApp.EventContext)
    #endif

    var logger: Logger {
        switch self {
        case let .request(context):
            context.logger
        #if Events
        case let .event(context):
            context.logger
        #endif
        }
    }

    var requestContext: SlackApp.Context? {
        guard case let .request(context) = self else { return nil }
        return context
    }

    #if Events
    var eventContext: SlackApp.EventContext? {
        guard case let .event(context) = self else { return nil }
        return context
    }
    #endif
}

typealias RequestHandler = @Sendable (DispatchContext, Request) async throws -> Void
public typealias RequestPayloadHandler<Payload: Sendable> =
    @Sendable (SlackApp.Context, Payload) async throws -> Void
public typealias RequestEnvelopePayloadHandler<Envelope: Sendable, Payload: Sendable> =
    @Sendable (SlackApp.Context, Envelope, Payload) async throws -> Void
#if Events
public typealias EventRequestPayloadHandler<Payload: Sendable> =
    @Sendable (SlackApp.EventContext, Payload) async throws -> Void
public typealias EventRequestEnvelopePayloadHandler<Envelope: Sendable, Payload: Sendable> =
    @Sendable (SlackApp.EventContext, Envelope, Payload) async throws -> Void
#endif
public typealias ErrorHandler = @Sendable (DispatchContext, Request, Swift.Error) async throws -> Void

public enum Request: Sendable {
    case interactive(InteractiveEnvelope)
    case slashCommand(SlashCommandsPayload)
    #if Events
    case event(EventsApiEnvelope<Event>)
    #endif
    case unsupported(String)
}

extension Request {
    /// Names the request type and the IDs handlers are registered with, for logs.
    var routingDescription: String {
        switch self {
        case let .interactive(envelope):
            envelope.body.routingDescription
        case let .slashCommand(payload):
            "slash command \"\(payload.command)\""
        #if Events
        case let .event(envelope):
            if let event = envelope.event.payload {
                "event \"\(event._type)\" (\(Swift.type(of: event)))"
            } else if case let .unsupported(type) = envelope.event {
                "unsupported event \"\(type)\""
            } else {
                "event"
            }
        #endif
        case let .unsupported(type):
            "unsupported request type \"\(type)\""
        }
    }
}

extension InteractivePayload {
    fileprivate var routingDescription: String {
        switch self {
        case let .shortcut(payload):
            describe(callbackId: payload.callbackId)
        case let .messageAction(payload):
            describe(callbackId: payload.callbackId)
        case let .blockActions(payload) where payload.blockActions.isEmpty:
            "\(_type) without actions"
        case let .blockActions(payload):
            "\(_type) with "
                + payload.blockActions
                .map { action in
                    "action_id \"\(action.actionId)\""
                        + (action.blockId.map { " and block_id \"\($0)\"" } ?? "")
                }
                .joined(separator: ", ")
        case let .viewSubmission(payload):
            describe(callbackId: payload.callbackId)
        case let .viewClosed(payload):
            describe(callbackId: payload.callbackId)
        case let .blockSuggestion(payload):
            "\(_type) with action_id \"\(payload.actionId)\""
                + (payload.blockId.map { " and block_id \"\($0)\"" } ?? "")
        case let .unsupported(type):
            "unsupported interactive payload type \"\(type)\""
        }
    }

    private func describe(callbackId: String?) -> String {
        "\(_type) with " + (callbackId.map { "callback_id \"\($0)\"" } ?? "no callback_id")
    }
}

private struct ActionKey: Hashable {
    let actionId: String
    let blockId: String?
}

#if Events
private struct TypedEventKey: Hashable {
    let typeName: String

    init<T: SlackEvent>(_: T.Type) {
        typeName = String(reflecting: T.self)
    }

    init(typeName: String) {
        self.typeName = typeName
    }
}
#endif

public class Router {
    private var interactiveHandler: RequestHandler?
    private var slashCommandHandlers: [String: RequestHandler] = [:]
    private var globalShortcutHandlers: [String: RequestHandler] = [:]
    private var messageShortcutHandlers: [String: RequestHandler] = [:]
    private var actionHandlers: [ActionKey: RequestHandler] = [:]
    private var blockActionHandlers: [String: RequestHandler] = [:]
    private var blockSuggestionHandlers: [ActionKey: RequestHandler] = [:]
    private var anyViewHandlers: [String: RequestHandler] = [:]
    private var viewSubmissionHandlers: [String: RequestHandler] = [:]
    private var viewClosedHandlers: [String: RequestHandler] = [:]
    #if Events
    private var eventHandler: RequestHandler?
    private var typedEventHandlers: [TypedEventKey: RequestHandler] = [:]
    #endif
    private var errorHandler: ErrorHandler?

    public init() {}

    struct FixedRouter {
        private let interactiveHandler: RequestHandler?
        private let slashCommandHandlers: [String: RequestHandler]
        private let globalShortcutHandlers: [String: RequestHandler]
        private let messageShortcutHandlers: [String: RequestHandler]
        private let actionHandlers: [ActionKey: RequestHandler]
        private let blockActionHandlers: [String: RequestHandler]
        private let blockSuggestionHandlers: [ActionKey: RequestHandler]
        private let anyViewHandlers: [String: RequestHandler]
        private let viewSubmissionHandlers: [String: RequestHandler]
        private let viewClosedHandlers: [String: RequestHandler]
        #if Events
        private let eventHandler: RequestHandler?
        private let typedEventHandlers: [TypedEventKey: RequestHandler]
        #endif
        private let errorHandler: ErrorHandler?

        init(from router: Router) {
            interactiveHandler = router.interactiveHandler
            slashCommandHandlers = router.slashCommandHandlers
            globalShortcutHandlers = router.globalShortcutHandlers
            messageShortcutHandlers = router.messageShortcutHandlers
            actionHandlers = router.actionHandlers
            blockActionHandlers = router.blockActionHandlers
            blockSuggestionHandlers = router.blockSuggestionHandlers
            anyViewHandlers = router.anyViewHandlers
            viewSubmissionHandlers = router.viewSubmissionHandlers
            viewClosedHandlers = router.viewClosedHandlers
            #if Events
            eventHandler = router.eventHandler
            typedEventHandlers = router.typedEventHandlers
            #endif
            errorHandler = router.errorHandler
        }

        @discardableResult
        func dispatch(context: DispatchContext, request: Request) async throws -> Bool {
            guard let handler = handler(for: request) else {
                context.logger.warning("No handler matched \(request.routingDescription)")
                return false
            }

            do {
                try await handler(context, request)
                return true
            } catch {
                if let errorHandler {
                    try await errorHandler(context, request, error)
                }
                throw error
            }
        }

        private func handler(for request: Request) -> RequestHandler? {
            switch request {
            case let .interactive(envelope):
                handler(for: envelope)
            case let .slashCommand(payload):
                slashCommandHandlers[payload.command]
            #if Events
            case let .event(payload):
                typedEventHandler(for: payload) ?? eventHandler
            #endif
            case .unsupported:
                nil
            }
        }

        private func handler(for envelope: InteractiveEnvelope) -> RequestHandler? {
            switch envelope.body {
            case let .shortcut(payload):
                if let callbackId = payload.callbackId,
                   let handler = globalShortcutHandlers[callbackId] {
                    return handler
                }
                return interactiveHandler
            case let .messageAction(payload):
                if let callbackId = payload.callbackId,
                   let handler = messageShortcutHandlers[callbackId] {
                    return handler
                }
                return interactiveHandler
            case let .blockActions(payload):
                if let handler = actionHandler(for: payload) {
                    return handler
                }
                if let callbackId = payload.callbackId,
                   let handler = blockActionHandlers[callbackId] {
                    return handler
                }
                return interactiveHandler
            // `onView` handlers in `anyViewHandlers` run their body for both view payload types, so they can serve
            // as the fallback when no handler is registered for the payload's own type. Type-specific handlers must
            // not: their body skips the other type, and returning one would report the request as handled without
            // an acknowledgement.
            case let .viewSubmission(payload):
                if let callbackId = payload.callbackId,
                   let handler = viewSubmissionHandlers[callbackId] ?? anyViewHandlers[callbackId] {
                    return handler
                }
                return interactiveHandler
            case let .viewClosed(payload):
                if let callbackId = payload.callbackId,
                   let handler = viewClosedHandlers[callbackId] ?? anyViewHandlers[callbackId] {
                    return handler
                }
                return interactiveHandler
            case let .blockSuggestion(payload):
                if let blockId = payload.blockId,
                   let handler = blockSuggestionHandlers[ActionKey(actionId: payload.actionId, blockId: blockId)] {
                    return handler
                }
                return blockSuggestionHandlers[ActionKey(actionId: payload.actionId, blockId: nil)] ?? interactiveHandler
            case .unsupported:
                return interactiveHandler
            }
        }

        /// Prefers a handler registered with both `action_id` and `block_id` for any action over one registered
        /// with `action_id` only.
        private func actionHandler(for payload: BlockActionsPayload) -> RequestHandler? {
            for action in payload.blockActions {
                if let blockId = action.blockId,
                   let handler = actionHandlers[ActionKey(actionId: action.actionId, blockId: blockId)] {
                    return handler
                }
            }
            for action in payload.blockActions {
                if let handler = actionHandlers[ActionKey(actionId: action.actionId, blockId: nil)] {
                    return handler
                }
            }
            return nil
        }

        #if Events
        private func typedEventHandler(for payload: EventsApiEnvelope<Event>) -> RequestHandler? {
            guard let event = payload.event.payload else { return nil }
            return typedEventHandlers[TypedEventKey(typeName: String(reflecting: Swift.type(of: event)))]
        }
        #endif
    }

    public func onInteractive(_ handler: @escaping RequestPayloadHandler<InteractiveEnvelope>) {
        interactiveHandler = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(payload) = request else { return }
            try await handler(context, payload)
        }
    }

    @available(*, deprecated, message: "Use onGlobalShortcut(_:handler:) instead. This misspelled API will be removed in a future version.")
    public func onGlboalShortcut(_ callbackId: String, handler: @escaping RequestPayloadHandler<GlobalShortcutPayload>) {
        onGlobalShortcut(callbackId, handler: handler)
    }

    public func onGlobalShortcut(_ callbackId: String, handler: @escaping RequestPayloadHandler<GlobalShortcutPayload>) {
        globalShortcutHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .shortcut(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    public func onMessageShortcut(_ callbackId: String, handler: @escaping RequestPayloadHandler<MessageShortcutPayload>) {
        messageShortcutHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .messageAction(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    public func onSlashCommand(
        _ command: String,
        handler: @escaping RequestPayloadHandler<SlashCommandsPayload>,
    ) {
        precondition(command.hasPrefix("/"), "A command should be registered with `/` prefix; e.g. `/command`")

        slashCommandHandlers[command] = { context, request in
            guard let context = context.requestContext,
                  case let .slashCommand(payload) = request,
                  payload.command == command else {
                return
            }
            try await handler(context, payload)
        }
    }

    /// Registers a handler for `block_actions` requests from an element with the given `action_id`.
    ///
    /// This matches interactions from messages, modals, and App Home alike, like Bolt's `app.action(...)` in
    /// JavaScript and Python and `app.blockAction(...)` in Java. Pass `blockId` to match only the element in that
    /// block. A handler registered with both IDs takes precedence over one registered with `actionId` only. To
    /// handle every action in a view, use ``onInteractive(_:)`` and check the payload's `callbackId`.
    public func onAction(
        _ actionId: String,
        blockId: String? = nil,
        handler: @escaping RequestPayloadHandler<BlockActionsPayload>,
    ) {
        actionHandlers[ActionKey(actionId: actionId, blockId: blockId)] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .blockActions(payload) = interactiveEnvelope.body,
                  payload.containsAction(actionId, blockId: blockId) else {
                return
            }
            try await handler(context, payload)
        }
    }

    /// Registers a handler for `block_suggestion` requests from an external select menu with the given `action_id`.
    ///
    /// Slack sends `block_suggestion` as the user types in an `external_select` or `multi_external_select` menu, like
    /// Bolt's `app.options(...)` in JavaScript and `app.blockSuggestion(...)` in Java. Respond with
    /// ``Ack/callAsFunction(options:)`` or ``Ack/callAsFunction(optionGroups:)``. Pass `blockId` to match only the menu
    /// in that block. A handler registered with both IDs takes precedence over one registered with `actionId` only.
    public func onBlockSuggestion(
        _ actionId: String,
        blockId: String? = nil,
        handler: @escaping RequestPayloadHandler<BlockSuggestionPayload>,
    ) {
        blockSuggestionHandlers[ActionKey(actionId: actionId, blockId: blockId)] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .blockSuggestion(payload) = interactiveEnvelope.body,
                  payload.actionId == actionId,
                  blockId == nil || payload.blockId == blockId else {
                return
            }
            try await handler(context, payload)
        }
    }

    /// Registers a handler for `block_actions` requests from any element in a view with the given `callback_id`.
    ///
    /// This was implemented incorrectly: it does not match Bolt, which matches block actions by the element's
    /// `action_id`. A view's `callback_id` also never matches elements in messages, which have no view. Use
    /// ``onAction(_:blockId:handler:)`` instead.
    @available(*, deprecated, message: "onBlockAction(_:) was implemented incorrectly: it does not match Bolt's app.action and app.blockAction, which match the element's action_id. It matches the containing view's callback_id instead, so it never matches elements in messages. Use onAction(_:blockId:handler:) to match an action_id, or onInteractive(_:) and check payload.callbackId to handle every action in a view. onBlockAction(_:) will be removed in a 2027 release.")
    public func onBlockAction(_ callbackId: String, handler: @escaping RequestPayloadHandler<BlockActionsPayload>) {
        blockActionHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .blockActions(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    /// Registers a handler for `view_submission` requests from a view with the given `callback_id`, like Bolt's
    /// `app.view` in JavaScript and Python.
    ///
    /// Unlike Bolt, if the view sets `notify_on_close`, this handler also receives `view_closed` requests, so it
    /// must acknowledge both payload types. Prefer ``onViewSubmission(_:handler:)`` and
    /// ``onViewClosed(_:handler:)``, which receive typed payloads.
    ///
    /// This is a fallback: a handler registered with ``onViewSubmission(_:handler:)`` or
    /// ``onViewClosed(_:handler:)`` for the same `callback_id` takes precedence for its payload type, regardless of
    /// registration order. Requests that no view handler matches go to ``onInteractive(_:)``.
    public func onView(_ callbackId: String, handler: @escaping RequestPayloadHandler<InteractivePayload>) {
        anyViewHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request else { return }
            if case let .viewSubmission(payload) = interactiveEnvelope.body,
               payload.callbackId == callbackId {
                try await handler(context, interactiveEnvelope.body)
            } else if case let .viewClosed(payload) = interactiveEnvelope.body,
                      payload.callbackId == callbackId {
                try await handler(context, interactiveEnvelope.body)
            }
        }
    }

    /// Registers a handler for `view_submission` requests from a view with the given `callback_id`.
    ///
    /// Like Bolt's `viewSubmission` in Java and `view_submission` in Python, this can be registered alongside
    /// ``onViewClosed(_:handler:)`` for the same `callback_id`. It takes precedence over ``onView(_:handler:)`` for
    /// `view_submission` requests, regardless of registration order.
    public func onViewSubmission(_ callbackId: String, handler: @escaping RequestPayloadHandler<ViewSubmissionPayload>) {
        viewSubmissionHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .viewSubmission(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    /// Registers a handler for `view_closed` requests from a view with the given `callback_id`.
    ///
    /// Slack sends `view_closed` only for views that set `notify_on_close`. Like Bolt's `viewClosed` in Java and
    /// `view_closed` in Python, this can be registered alongside ``onViewSubmission(_:handler:)`` for the same
    /// `callback_id`. It takes precedence over ``onView(_:handler:)`` for `view_closed` requests, regardless of
    /// registration order.
    public func onViewClosed(_ callbackId: String, handler: @escaping RequestPayloadHandler<ViewClosedPayload>) {
        viewClosedHandlers[callbackId] = { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .viewClosed(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    public func onError(_ handler: @escaping ErrorHandler) {
        errorHandler = handler
    }

    #if Events
    public func onEvent(_ handler: @escaping EventRequestPayloadHandler<EventsApiEnvelope<Event>>) {
        eventHandler = { context, request in
            guard let context = context.eventContext,
                  case let .event(payload) = request else { return }
            try await handler(context, payload)
        }
    }

    public func onEvent<T: SlackEvent>(
        _: T.Type,
        handler: @escaping EventRequestEnvelopePayloadHandler<EventsApiEnvelope<Event>, T>,
    ) {
        typedEventHandlers[TypedEventKey(T.self)] = { context, request in
            guard let context = context.eventContext,
                  case let .event(payload) = request,
                  let event = payload.event.payload as? T else {
                return
            }
            try await handler(context, payload, event)
        }
    }
    #endif
}
