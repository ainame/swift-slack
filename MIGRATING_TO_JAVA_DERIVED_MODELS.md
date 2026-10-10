# Migrating to Java-derived models

This release changes where swift-slack's Web API response and event types come from. They used to be inferred from recorded JSON samples; they are now translated from the model classes of [Slack's Java SDK](https://github.com/slackapi/java-slack-sdk).

A small bot that calls the Web API, reads responses through property chains and handles events usually needs only the import changes. Apps that spell out model types in their own signatures, store responses, or build models in tests need more of the steps below.

## What changed

- **The `SlackModels` module is gone.** Shared models such as `User`, `Message`, `File` and `Conversation` now live in `SlackClient` as `Components.Schemas.<Name>`, with a top-level alias of the same name (`User` is `Components.Schemas.User`). Response types have no top-level alias: keep writing `Components.Schemas.ChatPostMessageResponse`.
- **Top-level model classes are shared; nested ones are not.** Where the Java SDK uses its shared `Message` or `File` class, Web API responses and events now use the same Swift type. Where it declares a class inside a response or event, that type is specific to it (see [Types owned by one response or event](#types-owned-by-one-response-or-event)).
- **Models describe every field the Java SDK knows.** Fields that a single recorded sample happened to lack are now present. Across the 268 Web API responses, 469 top-level properties are new and none are gone.
- **Every property is optional except `ok` on responses and `_type` on events.** Slack omits fields depending on the method, the object and the workspace.
- **Requests, method names, response type names, event type names and `Event` cases are unchanged.** `slack.client.chatPostMessage(body: .json(...))`, `.ok.body.json`, `router.onEvent(MessageEvent.self)` and `case .message(let message)` keep working.

## Update dependencies and imports

Remove the `SlackModels` product from your package and replace `import SlackModels` with `import SlackClient`, or with `import SlackKit` in apps:

```swift
// Before
.product(name: "SlackKit", package: "swift-slack"),
.product(name: "SlackModels", package: "swift-slack"),

// After
.product(name: "SlackKit", package: "swift-slack"),
```

Replace `SlackModels.` prefixes with `Components.Schemas.`, or drop them to use the top-level alias:

```swift
// Before
func render(_ user: SlackModels.User) -> String

// After
func render(_ user: Components.Schemas.User) -> String
```

If your app declares its own `User`, `Message` or `File`, or imports SwiftUI (`App`, `Section`), keep the qualified spelling or add your own alias:

```swift
typealias SlackUser = SlackClient.Components.Schemas.User
```

## Renamed shared models

Forty former `SlackModels` names still exist with the same meaning, including `User`, `Message`, `File`, `Attachment`, `Team`, `Usergroup`, `BotProfile`, `Reaction`, `Reminder`, `Bookmark` and `Call`. The rest were inferred names that now map to the Java SDK's types:

| Before | After |
|---|---|
| `Channel` in `conversations.*` responses | `Conversation` |
| `ResponseMetadata` in 30 responses | `ErrorResponseMetadata` (or `WarningResponseMetadata`), whichever the Java SDK's response class uses; paginated responses keep `ResponseMetadata` with `nextCursor` |
| `FileElement`, `ItemFile` | `File` |
| `Member` (`users.list`) | `User` |
| `Log` (`team.integrationLogs`) | `IntegrationLog` |
| `Comment` | `FileComment` |
| `Barrier` | `InformationBarrier` |
| `Item`, `Record`, `Subtask` (Lists) | `ListRecord` |
| `Files`, `Messages` (`search.*`) | `SearchResult` |
| `InviteElement` | `ConnectInvite` |
| `WorkflowConfiguration` | `WorkflowDraftConfiguration` or `WorkflowPublishedConfiguration` |
| `WorkflowStep` (`workflow_step_execute`) | `WorkflowStepExecution` |
| `APITestArgs` | `Components.Schemas.APITestResponse.ArgsPayload` |
| `Enterprise`, `Container` (interaction payloads) | unchanged names, now declared in `SlackApp` |

## Types owned by one response or event

The Java SDK declares many objects inside a response or event class. They become nested types named after the property with a `Payload` suffix (`PayloadPayload` for array elements), and they are distinct types even when their names look alike.

| Property | Before | After |
|---|---|---|
| `MessageChangedEvent.message`, `MessageRepliedEvent.message` | `Message` | `<Event>.MessagePayload` |
| `MessageDeletedEvent.previousMessage` | `Message` | `MessageDeletedEvent.PreviousMessagePayload` |
| `FileCreatedEvent.file` and the other file events | `File` | `<Event>.FilePayload` (usually only `id`) |
| `ReactionAddedEvent.item`, `ReactionRemovedEvent.item`, ... | `Item` | `<Event>.ItemPayload` |
| `DndUpdatedEvent.dndStatus` | `DndStatus` | `DndUpdatedEvent.DndStatusPayload` |
| `MessageThreadBroadcastEvent.root` | `MessageRoot` | `MessageThreadBroadcastEvent.RootPayload` |
| `Message.edited`, `MessageEvent.edited`, ... | `Edited` | `<Owner>.EditedPayload` |
| `ReactionsGetResponse.message` | `Message` | `Components.Schemas.ReactionsGetResponse.MessagePayload` |
| `AdminConversationsGetConversationPrefsResponse.prefs` | `Prefs` | `Components.Schemas.AdminConversationsGetConversationPrefsResponse.PrefsPayload` |

A helper such as `func render(_ message: Message)` therefore no longer accepts `event.message` from a `message_changed` handler. Read the fields you need into your own value instead:

```swift
struct EditedText { var ts: String?; var text: String? }

router.onEvent(MessageChangedEvent.self) { _, _, event in
    let edited = EditedText(ts: event.message?.ts, text: event.message?.text)
    let before = event.previousMessage?.message?.text
}
```

Prefer type inference and property chains to spelling nested names out:

```swift
let whoCanPost = response.prefs?.whoCanPost?._type  // [String]?
let step = workflow.steps?.first                    // AppWorkflow.StepsPayloadPayload
```

## User and team profiles

`UserProfile` and `Profile` were shared before. The Java SDK has several profile shapes, so the type depends on where it comes from:

| Where | Type |
|---|---|
| `User.profile` (`users.info`, `users.list`, interaction payloads) | `User.ProfilePayload` |
| `users.profile.get`, `users.profile.set`, `users.setPhoto` | `Components.Schemas.<Response>.ProfilePayload` |
| `AppMentionEvent.userProfile` | `AppMentionEvent.UserProfilePayload` (a smaller shape without `email`) |
| `team.profile.get` | `Components.Schemas.TeamProfileGetResponse.ProfilePayload` |

`User.ProfilePayload` has no `name`, `isRestricted` or `isUltraRestricted`; read `user.name`, `user.isRestricted` and `user.isUltraRestricted` instead.

## Dictionaries

A JSON object with arbitrary keys becomes a struct whose values are in `additionalProperties`:

```swift
// Before
let field = user.profile?.fields?["Xf123"]?.value
let input = workflow.steps?.first?.inputs?["message"]

// After
let field = user.profile?.fields?.additionalProperties["Xf123"]?.value
let input = workflow.steps?.first?.inputs?.additionalProperties["message"]
```

## Changed properties

| Property | Before | After |
|---|---|---|
| `File` image sizes (`originalW`, `thumb360W`, ...) | `String?` | `Int?` |
| `Message._type`, `Action._type`, `Bookmark._type` | `String` | `String?` |
| `WorkflowStepOutput.type` | `type` | `_type` |
| `AppRequest.message` | `Message?` | `String?` |
| `Field.alt` (attachment fields) | `String?` | removed; `Field` has `title`, `value` and `short` |
| `ResponseMetadata.warnings` | `[OpenAPIValueContainer]?` | `[String]?` |
| `File.attachments` | `[OpenAPIValueContainer]?` | `[Attachment]?` |
| `Attachment.videoHtml` | `String?` | `AttachmentVideoHtml?` (see below) |
| `Attachment.videoHtmlWidth`, `videoHtmlHeight` | `Int?` | `Double?` |
| `MessageChangedEvent.previousMessage` | `Message?` | `MessageChangedEventPreviousMessage?` (see below) |
| Workflow step form elements `isLong`, `defaultValue`, `enumValues` | | `long`, `_default`, `_enum` |

The properties whose type differs from the Java SDK's declaration (because Slack sends another JSON type) say so in their documentation comment.

## Values with several shapes

A few fields can arrive in more than one JSON shape. They are enums with a read-only accessor per shape:

```swift
// Attachment.video_html: a string of HTML or an object with `source`
let html = attachment.videoHtml?.html
let source = attachment.videoHtml?.video?.source

// message_changed: the previous message, or nothing
let before = event.previousMessage?.message

// admin.workflows.search: workflow step input values
let value = input?.value
let text = value?.stringValue          // "hello"
let users = value?.stringValues        // ["U1", "U2"]
let blocks = value?.interactiveBlocks  // [Block]
let flag = value?.boolValue            // true
let form = value?.form                 // elements and required

// Lists cell values, whose JSON type depends on the column
let checked = field.value?.boolValue
```

To build one, use the enum case: `Attachment(videoHtml: .case1("<iframe>…</iframe>"))`.

## Building models in tests

Every model has a memberwise initializer with defaulted optional arguments, now including events. Arguments follow the Java SDK's field order, which differs from the alphabetical order before, so reorder the labels:

```swift
// Before
Components.Schemas.ChatPostMessageResponse(channel: "C1", ok: true)

// After
Components.Schemas.ChatPostMessageResponse(ok: true, channel: "C1")
let event = MessageEvent(_type: "message", text: "hello")
```

Dictionaries need their wrapper: `User.ProfilePayload(fields: .init(additionalProperties: ["Xf123": .init(value: "Engineering")]))`.

## Events

Event types are aliases of `Components.Schemas` types declared in `SlackApp`. Handlers registered with `router.onEvent(MessageEvent.self)` and `switch` statements over `Event` are unchanged. Events gained the fields the Java SDK declares and use shared models where it does (`MessageEvent.files` is `[File]?`); see [Types owned by one response or event](#types-owned-by-one-response-or-event) for the nested ones.

## Block Kit

- `Block`, `View` and the element enums (`ActionElementType`, `ContextElementType`, `SectionAccessory`, `InputElementType`, and the rich text element enums) gained `.unknown(type:payload:)`. A block or element type that SlackBlockKit does not model no longer fails the whole response.
- New types: `AlertBlock`, `CardBlock`, `CarouselBlock`, `ContextActionsBlock`, `FeedbackButtonsElement`, `IconButtonElement`, `URLInputElement`, `WorkflowButtonElement` and `FeedbackButtonObject`, with matching enum cases (`.alert`, `.card`, `.carousel`, `.contextActions`, `.workflowButton`, `.urlInput`).
- Exhaustive `switch` statements need cases (or `default`) for `.unknown` and the new cases.
- `MultiStaticSelectElement.options` is optional, and `optionGroups` is new.
- `TimePickerElement.timezone` is new.
- `ConversationFilterObject`, `TriggerObject` and `DispatchActionConfigurationObject` now read and write Slack's snake_case keys. Filters built by apps used keys that Slack ignored before.

## Known gaps

- `IMCreatedEvent.channel` is an untyped object, because the Java SDK has not modelled it yet.
- `Conversation` no longer has fields that only appeared in other methods' samples, such as `memberCount` and `isFrozen`. Admin APIs that return them have their own response types (`AdminConversationsSearchResponse`).
