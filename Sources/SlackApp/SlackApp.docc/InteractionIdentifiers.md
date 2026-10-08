# Choosing Between action_id and callback_id

Route interactions by the identifier that Slack sends for each kind of request.

## Overview

Slack identifies interactions with several strings, and each ``Router`` method matches one of them:

- term `action_id`: Identifies an interactive element, such as a button or select menu. It needs to be unique only within its block, so the same `action_id` can appear in many messages and views.
- term `block_id`: Identifies the block that contains the element. Use it to tell apart elements that share an `action_id`.
- term `callback_id`: Identifies a view, such as a modal, or a shortcut. It is a label you choose, not a reference to one open view: every modal built with the same `callback_id` shares it.
- term `view_id`: Identifies one open view. Slack assigns it, and `views.update` uses it, or your own `external_id`, to choose the view to update.
- term `private_metadata`: Carries state you attach to a view. Slack sends it back in `view_submission` and `block_actions` requests and does not show it to users.

As an analogy from UIKit, `action_id` is like the `sender` of an action, `callback_id` is like the class of the view controller that shows it, and `view_id` is like a reference to that view controller instance.

> Important: This guide summarizes Slack's documentation as of October 2026. Slack's platform changes over time, so confirm the details on the official pages listed at the end of this guide before you rely on them.

The examples build views with `SlackBlockKitDSL`. Add that product to your target alongside `SlackKit`, and `import SlackBlockKitDSL`.

## Which identifier each request uses

| Request | Router method | Matches |
|---|---|---|
| `block_actions`: an element was clicked or changed, in a message, modal, or App Home | ``Router/onAction(_:blockId:handler:)`` | `action_id`, and `block_id` when given |
| `block_suggestion`: an external select menu needs options | ``Router/onBlockSuggestion(_:blockId:handler:)`` | `action_id`, and `block_id` when given |
| `view_submission`: a modal's submit button was clicked | ``Router/onViewSubmission(_:handler:)`` | the view's `callback_id` |
| `view_closed`: a modal was closed, if it set `notify_on_close` | ``Router/onViewClosed(_:handler:)`` | the view's `callback_id` |
| Global shortcut | ``Router/onGlobalShortcut(_:handler:)`` | the shortcut's `callback_id` |
| Message shortcut | ``Router/onMessageShortcut(_:handler:)`` | the shortcut's `callback_id` |

A `block_actions` request has no top-level `callback_id`. When the element is in a modal or App Home, the request carries the containing view, and ``BlockActionsPayload/callbackId`` returns that view's `callback_id`. For an element in a message, there is no view, so it returns `nil`.

Clicking a button inside a modal sends `block_actions`, not `view_submission`. Handle it with `onAction`, not `onView`, `onViewSubmission`, or `onViewClosed`. Only the modal's submit button sends `view_submission`.

## Handle a button in a modal

Match the button's `action_id`. When the same `action_id` appears in more than one view, check ``BlockActionsPayload/callbackId`` to find out which view it came from.

Slack doesn't accept a `response_action` in reply to `block_actions`, so to change the modal, acknowledge the request and call `views.update` with the view's ID.

```swift
router.onAction("add_item") { context, payload in
    try await context.ack()

    guard payload.callbackId == "todo_modal",
          let viewId = payload.view?.id else {
        return
    }

    let updated = Modal(title: Text("To-do")) {
        Section { Text("Added an item.") }
    }
    .submit(Text("Save"))
    .callbackId("todo_modal")

    _ = try await context.client.viewsUpdate(
        body: .json(.init(viewId: viewId, view: updated.asView()))
    )
}
```

`views.update` replaces the view with the one you pass, so build the new view with every field it needs, including its `callback_id`, `submit` button, and `private_metadata`.

> Note: Slack's `views.update` also accepts the view's `hash` to reject an update when the view changed after the button was clicked. Slack sends it as `view.hash`, which swift-slack's `View` doesn't expose yet, so this example updates the view without that check.

## Move between steps of a modal

Give each step its own `callback_id`, so each step's submission goes to its own handler.

When the user moves forward by submitting the modal, reply to the `view_submission` with ``Ack/callAsFunction(responseAction:view:)``. `.update` replaces the current view, and `.push` adds a view on top of it. A plain ``Ack/callAsFunction()`` closes the submitted view. When the user moves forward by clicking a button inside the modal, call `views.update` as in the previous section, or `views.push` with the request's `trigger_id`.

Slack keeps an input's value across an update only when the new view has an input with the same `block_id` and `action_id`. Values from inputs that the next step removes aren't sent with later submissions, so carry them forward in `private_metadata`.

```swift
router.onViewSubmission("signup_step1") { context, payload in
    let name = payload.view.state?["name_block", "name"]?.value ?? ""

    let step2 = Modal(title: Text("Sign up")) {
        Input("Email") {
            PlainTextInput("email")
        }
        .blockId("email_block")
    }
    .submit(Text("Finish"))
    .callbackId("signup_step2")
    .privateMetadata(name)

    try await context.ack(responseAction: .update, view: step2.asView())
}

router.onViewSubmission("signup_step2") { context, payload in
    let name = payload.view.privateMetadata ?? ""
    let email = payload.view.state?["email_block", "email"]?.value ?? ""
    try await context.ack()
    context.logger.info("Signed up \(name) <\(email)>")
}
```

A modal sends `view_submission` only if it has a `submit` button, which Slack requires when the modal contains an input block.

## Slack documentation

- [block_actions payload](https://docs.slack.dev/reference/interaction-payloads/block_actions-payload)
- [View interactions payloads](https://docs.slack.dev/reference/interaction-payloads/view-interactions-payload)
- [Modals](https://docs.slack.dev/surfaces/modals)
- [Modal view fields](https://docs.slack.dev/reference/views/modal-views)
- [views.update](https://docs.slack.dev/reference/methods/views.update)
- [Button element](https://docs.slack.dev/reference/block-kit/block-elements/button-element)
