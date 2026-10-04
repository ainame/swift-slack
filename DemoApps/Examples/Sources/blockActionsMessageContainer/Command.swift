import Foundation
import OpenAPIRuntime
import SlackBlockKitDSL
import SlackKit

@main
struct Command {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["SLACK_OAUTH_TOKEN"],
              let appToken = ProcessInfo.processInfo.environment["SLACK_APP_LEVEL_TOKEN"],
              let channel = ProcessInfo.processInfo.environment["SLACK_REPRO_CHANNEL_ID"],
              let unfurlUrl = ProcessInfo.processInfo.environment["SLACK_REPRO_UNFURL_URL"] else {
            print("Please set SLACK_OAUTH_TOKEN, SLACK_APP_LEVEL_TOKEN, SLACK_REPRO_CHANNEL_ID, and SLACK_REPRO_UNFURL_URL.")
            print("SLACK_REPRO_CHANNEL_ID should be a channel ID like C0123456789.")
            print("SLACK_REPRO_UNFURL_URL should be a URL whose domain is configured for your Slack app link unfurls.")
            Foundation.exit(1)
        }

        let router = Router()

        router.onInteractive { context, interactive in
            try await context.ack()
            switch interactive.body {
            case let .blockActions(payload):
                print("block_actions received")
                print("container.type: \(payload.container._type)")
                print("container: \(payload.container)")
                print("actions: \(payload.blockActions.map { String(describing: $0) })")
            case let .unsupported(type):
                print("unsupported interactive payload type: \(type)")
            default:
                print("interactive payload type: \(interactive._type)")
            }
        }

        let app = SlackApp(
            configuration: .init(
                userAgent: "BlockActionsMessageContainerRepro/1.0",
                appToken: appToken,
                token: token,
            ),
            router: router,
            mode: .socketMode(),
        )

        try await app.run { slack in
            let blocks = ReproMessageBlocks().blocks

            _ = try await slack.client.chatPostMessage(
                body: .json(
                    .init(
                        blocks: blocks,
                        channel: channel,
                        text: "message-container block_actions repro",
                    ),
                ),
            )

            let unfurlSeedResult = try await slack.client.chatPostMessage(
                body: .json(
                    .init(
                        channel: channel,
                        text: "message_attachment block_actions repro via unfurl: \(unfurlUrl)",
                    ),
                ),
            )

            let seedResponse = try requireChatPostMessageResponse(unfurlSeedResult, context: "unfurl seed message")
            guard let seedTs = seedResponse.ts else {
                print("Failed to read ts from chat.postMessage response for unfurl seed message.")
                Foundation.exit(1)
            }

            let unfurlResult = try await slack.client.chatUnfurl(
                body: .json(
                    .init(
                        channel: channel,
                        ts: seedTs,
                        unfurls: buildMessageAttachmentUnfurlPayload(url: unfurlUrl),
                    ),
                ),
            )
            let unfurlResponse = try requireChatUnfurlResponse(unfurlResult)
            if !unfurlResponse.ok {
                print("chat.unfurl failed: \(unfurlResponse.error ?? "unknown_error")")
                print("hint: verify link unfurl is enabled for this app and the URL domain is configured in app settings.")
                Foundation.exit(1)
            }

            print("Posted repro messages to channel \(channel). Click both buttons in Slack.")
            print("Expected interaction types:")
            print("- message blocks button -> block_actions (container.type = message)")
            print("- unfurl button -> block_actions (container.type = message_attachment)")
            print("If unfurl button is missing, app/domain setup for link unfurls is incomplete.")
        }
    }
}

private func buildMessageAttachmentUnfurlPayload(url: String) throws -> OpenAPIObjectContainer {
    let payload = [
        url: MessageAttachmentUnfurlPayload(blocks: MessageAttachmentUnfurlBlocks().blocks),
    ]
    let data = try JSONEncoder().encode(payload)
    return try JSONDecoder().decode(OpenAPIObjectContainer.self, from: data)
}

private struct MessageAttachmentUnfurlPayload: Codable {
    let blocks: [Block]
}

private func requireChatPostMessageResponse(
    _ output: Operations.ChatPostMessage.Output,
    context: String,
) throws -> Components.Schemas.ChatPostMessageResponse {
    guard case let .ok(okOutput) = output,
          case let .json(response) = okOutput.body else {
        throw ReproError.unexpectedOutput("\(context): unexpected output shape")
    }
    guard response.ok else {
        throw ReproError.apiError("\(context): \(response.error ?? "unknown_error")")
    }
    return response
}

private func requireChatUnfurlResponse(
    _ output: Operations.ChatUnfurl.Output,
) throws -> Components.Schemas.ChatUnfurlResponse {
    guard case let .ok(okOutput) = output,
          case let .json(response) = okOutput.body else {
        throw ReproError.unexpectedOutput("chat.unfurl: unexpected output shape")
    }
    return response
}

private enum ReproError: Error, CustomStringConvertible {
    case unexpectedOutput(String)
    case apiError(String)

    var description: String {
        switch self {
        case let .unexpectedOutput(message), let .apiError(message):
            message
        }
    }
}

private struct ReproMessageBlocks: SlackView {
    @BlockBuilder
    var blocks: [Block] {
        Section {
            Text("Click the button below to send a `block_actions` payload from a message container.")
                .type(.mrkdwn)
        }

        Actions {
            Button("Reproduce bug")
                .actionId("repro_message_container")
                .value("repro")
        }
        .blockId("repro_message_container")
    }
}

private struct MessageAttachmentUnfurlBlocks: SlackView {
    @BlockBuilder
    var blocks: [Block] {
        Section {
            Text("Click the button below to send a `block_actions` payload from an unfurl attachment container.")
                .type(.mrkdwn)
        }

        Actions {
            Button("Reproduce message_attachment")
                .actionId("repro_message_attachment_unfurl")
                .value("repro")
        }
    }
}
