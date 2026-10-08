import Foundation
import SlackBlockKitDSL
import SlackKit

/// Checks which fields Slack accepts inside a modal's `view` object, over Socket Mode.
///
/// Slack's payloads include `id`, `state`, and `hash` in each view, but `views.update` takes the view's ID and
/// `hash` as separate arguments. `/viewfields` opens a modal whose buttons each send a request and show Slack's
/// answer in the modal; the terminal prints every request and response.
///
/// - The `raw:` buttons send hand-built JSON, so they show what Slack accepts regardless of how swift-slack encodes
///   views.
/// - The `swift-slack:` button and the modal's submit button send the decoded `id`, `state`, and `hash` through
///   swift-slack's own models, with `views.update` and `ack(responseAction: .update, view:)`. They show whether an app
///   can send a view built from a decoded one.
///
/// Slack app setup: enable Socket Mode and Interactivity, and create the `/viewfields` slash command.
@main
struct ViewFieldsCheckCommand {
    static let callbackId = "view_fields_check"
    static let staleHash = "1000000000.stale000"

    enum Check: String, CaseIterable {
        case rawDecodedFields = "raw_decoded_fields"
        case rawHashInView = "raw_hash_in_view"
        case rawHashArgument = "raw_hash_argument"
        case rawStaleHashArgument = "raw_stale_hash_argument"
        case rawPushHashInView = "raw_push_hash_in_view"
        case clientDecodedFields = "client_decoded_fields"

        var label: String {
            switch self {
            case .rawDecodedFields: "raw: update with id, state, hash in view"
            case .rawHashInView: "raw: update with hash in view"
            case .rawHashArgument: "raw: update with hash argument"
            case .rawStaleHashArgument: "raw: update with stale hash argument"
            case .rawPushHashInView: "raw: push with hash in view"
            case .clientDecodedFields: "swift-slack: update with decoded fields"
            }
        }
    }

    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["SLACK_OAUTH_TOKEN"],
              let appToken = ProcessInfo.processInfo.environment["SLACK_APP_LEVEL_TOKEN"] else {
            print("❌ Please set SLACK_OAUTH_TOKEN and SLACK_APP_LEVEL_TOKEN environment variables")
            print("   SLACK_OAUTH_TOKEN: Bot token (starts with xoxb-)")
            print("   SLACK_APP_LEVEL_TOKEN: App-level token (starts with xapp-)")
            exit(1)
        }

        let router = Router()

        router.onSlashCommand("/viewfields") { context, payload in
            try await context.ack()
            _ = try await context.client.viewsOpen(
                body: .json(.init(triggerId: payload.triggerId, view: .modal(modal(results: [])))),
            )
        }

        for check in Check.allCases {
            router.onAction(check.rawValue) { context, payload in
                try await context.ack()
                guard case let .modal(decoded) = payload.view, let viewId = decoded.id else {
                    return
                }
                let previous = results(in: decoded)
                let next = modal(results: previous + ["*\(check.label)*: sent"])
                print("== \(check.label): view_id \(viewId), hash \(decoded.hash ?? "none")")

                let line: String
                // The view to show the result in. A successful push puts a new view on top, so its result goes there.
                var resultViewId = viewId
                switch check {
                case .rawDecodedFields:
                    var view = try jsonObject(View.modal(next))
                    view["id"] = decoded.id
                    view["state"] = try decoded.state.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
                    view["hash"] = decoded.hash
                    line = try await summary(check, callSlack(token: token, "views.update", ["view_id": viewId, "view": view]))
                case .rawHashInView:
                    var view = try jsonObject(View.modal(next))
                    view["hash"] = decoded.hash
                    line = try await summary(check, callSlack(token: token, "views.update", ["view_id": viewId, "view": view]))
                case .rawHashArgument:
                    let body: [String: Any] = try ["view_id": viewId, "hash": decoded.hash ?? "", "view": jsonObject(View.modal(next))]
                    line = try await summary(check, callSlack(token: token, "views.update", body))
                case .rawStaleHashArgument:
                    let body: [String: Any] = try ["view_id": viewId, "hash": staleHash, "view": jsonObject(View.modal(next))]
                    line = try await summary(check, callSlack(token: token, "views.update", body))
                case .rawPushHashInView:
                    var view = try jsonObject(View.modal(next))
                    view["hash"] = decoded.hash
                    let body: [String: Any] = ["trigger_id": payload.triggerId ?? "", "view": view]
                    let response = try await callSlack(token: token, "views.push", body)
                    if let pushedViewId = (response["view"] as? [String: Any])?["id"] as? String {
                        resultViewId = pushedViewId
                    }
                    line = summary(check, response)
                case .clientDecodedFields:
                    let view = View.modal(withDecodedFields(next, from: decoded))
                    print("→ swift-slack views.update view keys: \(try jsonObject(view).keys.sorted())")
                    let response = try await context.client.viewsUpdate(body: .json(.init(viewId: viewId, view: view)))
                    let json = try response.ok.body.json
                    print("← ok: \(json.ok), error: \(json.error ?? "none"), messages: \(json.responseMetadata?.messages ?? [])")
                    let outcome = json.ok ? "ok" : "error \(json.error ?? "unknown")"
                    line = (["*\(check.label)*: \(outcome)"] + (json.responseMetadata?.messages ?? [])).joined(separator: " — ")
                }

                // Show the result with a fresh view that carries no decoded fields.
                print("== \(line)")
                _ = try await context.client.viewsUpdate(
                    body: .json(.init(viewId: resultViewId, view: .modal(modal(results: previous + [line])))),
                )
            }
        }

        // The submit button sends view_submission. Acknowledging with a view built from the decoded one shows the new
        // result line if Slack accepts it; if Slack rejects the acknowledgement, the modal shows an error instead.
        router.onViewSubmission(callbackId) { context, payload in
            guard case let .modal(decoded) = payload.view else {
                try await context.ack()
                return
            }
            let line = "*swift-slack: ack update with decoded fields*: accepted"
            let view = View.modal(withDecodedFields(modal(results: results(in: decoded) + [line]), from: decoded))
            print("== ack update: hash \(decoded.hash ?? "none")")
            print("→ swift-slack ack view keys: \(try jsonObject(view).keys.sorted())")
            try await context.ack(responseAction: .update, view: view)
        }

        let app = SlackApp(
            configuration: .init(
                userAgent: "ViewFieldsCheck/1.0",
                appToken: appToken,
                token: token,
            ),
            router: router,
            mode: .socketMode(),
        )

        print("🚀 Starting view fields check. Run /viewfields in Slack.")
        try await app.run()
    }

    /// The check modal. Result lines are shown in the modal and carried in `private_metadata`.
    static func modal(results: [String]) -> ModalView {
        // private_metadata holds at most 3000 characters, so keep only the latest results.
        let results = Array(results.suffix(6))
        let view = Modal(title: Text("View fields check")) {
            Section {
                Text(results.isEmpty ? "_No checks run yet._" : results.joined(separator: "\n"))
                    .type(.mrkdwn)
            }
            Actions {
                for check in Check.allCases {
                    Button(check.label).actionId(check.rawValue)
                }
            }
            .blockId("checks")
        }
        .submit(Text("Ack update"))
        .close(Text("Close"))
        .callbackId(callbackId)
        .privateMetadata(results.joined(separator: "\n"))
        .asView()

        guard case let .modal(modal) = view else {
            preconditionFailure("Modal renders a modal view")
        }
        return modal
    }

    static func results(in view: ModalView) -> [String] {
        (view.privateMetadata ?? "").split(separator: "\n").map(String.init)
    }

    /// Copies `modal` with the `id`, `state`, and `hash` from `decoded`, as an app does when it builds a view from one
    /// Slack sent.
    static func withDecodedFields(_ modal: ModalView, from decoded: ModalView) -> ModalView {
        ModalView(
            title: modal.title,
            blocks: modal.blocks,
            close: modal.close,
            submit: modal.submit,
            privateMetadata: modal.privateMetadata,
            callbackId: modal.callbackId,
            clearOnClose: modal.clearOnClose,
            notifyOnClose: modal.notifyOnClose,
            externalId: modal.externalId,
            submitDisabled: modal.submitDisabled,
            state: decoded.state,
            id: decoded.id,
            hash: decoded.hash,
        )
    }

    static func jsonObject(_ view: View) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(view)) as? [String: Any] ?? [:]
    }

    /// Calls a Web API method with a hand-built JSON body and returns Slack's response object.
    static func callSlack(token: String, _ method: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let data = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = data
        print("→ \(method) \(String(decoding: data, as: UTF8.self))")
        let (response, _) = try await URLSession.shared.data(for: request)
        print("← \(String(decoding: response, as: UTF8.self))")
        return try JSONSerialization.jsonObject(with: response) as? [String: Any] ?? [:]
    }

    static func summary(_ check: Check, _ response: [String: Any]) -> String {
        let ok = response["ok"] as? Bool ?? false
        var parts = ["*\(check.label)*: \(ok ? "ok" : "error \(response["error"] ?? "unknown")")"]
        if let messages = (response["response_metadata"] as? [String: Any])?["messages"] as? [String] {
            parts.append(contentsOf: messages)
        }
        return parts.joined(separator: " — ")
    }
}
