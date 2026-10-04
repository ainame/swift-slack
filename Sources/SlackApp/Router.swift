import Foundation
import Logging
import OpenAPIRuntime
import SlackClient

public enum DispatchContext: Sendable {
    case request(SlackApp.Context)
    #if Events
    case event(SlackApp.EventContext)
    #endif

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

private enum InteractiveHandler {
    case interactive(RequestHandler)
    case shortcut(RequestHandler)
    case messageShortcut(RequestHandler)
    case blockAction(RequestHandler)
    case view(RequestHandler)
    case viewSubmission(RequestHandler)
    case viewClosed(RequestHandler)

    var handler: RequestHandler {
        switch self {
        case let .interactive(handler),
             let .shortcut(handler),
             let .messageShortcut(handler),
             let .blockAction(handler),
             let .view(handler),
             let .viewSubmission(handler),
             let .viewClosed(handler):
            handler
        }
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
    private var viewHandlers: [String: InteractiveHandler] = [:]
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
        private let viewHandlers: [String: InteractiveHandler]
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
            viewHandlers = router.viewHandlers
            #if Events
            eventHandler = router.eventHandler
            typedEventHandlers = router.typedEventHandlers
            #endif
            errorHandler = router.errorHandler
        }

        @discardableResult
        func dispatch(context: DispatchContext, request: Request) async throws -> Bool {
            guard let handler = handler(for: request) else {
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
            case let .viewSubmission(payload):
                if let callbackId = payload.callbackId,
                   let handler = viewHandlers[callbackId] {
                    return handler.handler
                }
                return interactiveHandler
            case let .viewClosed(payload):
                if let callbackId = payload.callbackId,
                   let handler = viewHandlers[callbackId] {
                    return handler.handler
                }
                return interactiveHandler
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

    /// Registers a handler for `block_actions` requests from any element in a view with the given `callback_id`.
    ///
    /// This does not match an element's `action_id`, and never matches elements in messages, which have no view.
    @available(*, deprecated, message: "onBlockAction(_:) matches the containing view's callback_id, not the element's action_id. To match an element's action_id, like Bolt's app.action or app.blockAction, use onAction(_:blockId:handler:). To handle every action in a view, use onInteractive(_:) and check payload.callbackId. onBlockAction(_:) will be removed in a 2027 release.")
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

    public func onView(_ callbackId: String, handler: @escaping RequestPayloadHandler<InteractivePayload>) {
        viewHandlers[callbackId] = .view { context, request in
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

    public func onViewSubmission(_ callbackId: String, handler: @escaping RequestPayloadHandler<ViewSubmissionPayload>) {
        viewHandlers[callbackId] = .viewSubmission { context, request in
            guard let context = context.requestContext,
                  case let .interactive(interactiveEnvelope) = request,
                  case let .viewSubmission(payload) = interactiveEnvelope.body,
                  payload.callbackId == callbackId else {
                return
            }
            try await handler(context, payload)
        }
    }

    public func onViewClosed(_ callbackId: String, handler: @escaping RequestPayloadHandler<ViewClosedPayload>) {
        viewHandlers[callbackId] = .viewClosed { context, request in
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
