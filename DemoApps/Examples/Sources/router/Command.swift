import Foundation
import SlackBlockKitDSL
import SlackKit

@main
struct Command {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["SLACK_OAUTH_TOKEN"],
              let appToken = ProcessInfo.processInfo.environment["SLACK_APP_LEVEL_TOKEN"] else {
            print("Prepare SLACK_OAUTH_TOKEN to run this script")
            exit(1)
        }

        let router = Router()

        router.onEvent { _, envelope in
            switch envelope.event {
            case .appMention:
                print("onEvent: appMention")
            case .message:
                print("onEvent: meessage")
            default:
                break
            }
        }

        router.onEvent(AppMentionEvent.self) { _, _, _ in
            print("onEvent: AppMentionEvent")
        }

        router.onInteractive { context, envelope in
            try await context.ack()

            switch envelope.body {
            case .shortcut:
                print("onInteractive: .shortcut")
            case .messageAction:
                print("onInteractive: .messageAction")
            case .blockActions:
                print("onInteractive: .blockActions")
            case .viewSubmission:
                print("onInteractive: .viewSubmission")
            case .viewClosed:
                print("onInteractive: .viewClosed")
            case .blockSuggestion:
                print("onInteractive: .blockSuggestion")
            case .unsupported:
                print("onInteractive: .unsupported")
            }
        }

        router.onGlobalShortcut("run-something") { context, payload in
            try await context.ack()
            print("onGlobalShortcut: \(payload._type) \(payload.callbackId!)")
        }

        router.onAction("run-something") { context, payload in
            try await context.ack()
            print("onAction: \(payload._type) \(payload.blockActions.map(\.actionId))")
        }

        router.onEvent(MessageEvent.self) { _, _, payload in
            guard let text = payload.text,
                  text.contains("Hello") || text.contains("World") else { return }
            print("onEvent(MessageEvent.self): \(text)")
        }

        let app = SlackApp(
            configuration: .init(
                userAgent: "SwiftBot",
                appToken: appToken,
                token: token,
            ),
            router: router,
            mode: .socketMode(),
        )
        try await app.run()
    }
}
