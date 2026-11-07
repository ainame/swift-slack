import Logging
import SlackKit

/// Thumbs up and down buttons under every reply, as the Slack agent docs recommend.
enum Feedback {
    static let actionId = "feedback"

    static func blocks() -> [Block] {
        [
            .contextActions(ContextActionsBlock(elements: [
                .feedbackButtons(FeedbackButtonsElement(
                    positiveButton: FeedbackButtonObject(
                        text: TextObject(type: .plainText, text: "Good response"),
                        value: "good",
                        accessibilityLabel: "Submit positive feedback on this response",
                    ),
                    negativeButton: FeedbackButtonObject(
                        text: TextObject(type: .plainText, text: "Bad response"),
                        value: "bad",
                        accessibilityLabel: "Submit negative feedback on this response",
                    ),
                    actionId: actionId,
                )),
            ])),
        ]
    }

    static func register(on router: Router, logger: Logger) {
        router.onAction(actionId) { context, payload in
            try await context.ack()
            guard let value = payload.blockActions.first(where: { $0.actionId == actionId })?.value,
                  let channel = payload.container.channelId,
                  let user = payload.user.id else {
                return
            }
            logger.info("Received feedback", metadata: ["value": "\(value)", "message": "\(payload.container.messageTs ?? "")"])

            let text = value == "good"
                ? "Thanks for the feedback! :tada:"
                : "Sorry that wasn't helpful. Try rephrasing your question and I'll give it another shot."
            _ = try await context.client.chatPostEphemeral(body: .json(.init(
                channel: channel,
                text: text,
                threadTs: payload.messageThreadTs,
                user: user,
            ))).ok.body.json.checked("chat.postEphemeral")
        }
    }
}

extension BlockActionsPayload {
    /// The thread of the message the action came from, where a notice about it goes. A top-level reply in a
    /// code channel has none, so the notice goes to the channel.
    var messageThreadTs: String? {
        message.map(\.threadTs) ?? container.messageTs
    }
}
