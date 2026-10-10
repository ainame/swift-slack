# Migrating to Java-derived models

This release changes where swift-slack's Web API response and event types come from. They used to be inferred from recorded JSON samples; they are now translated from the model classes of [Slack's Java SDK](https://github.com/slackapi/java-slack-sdk). Most call sites compile unchanged. The main breaks are the removal of the `SlackModels` module and the renamed nested types.

## What changed

- **The `SlackModels` module is gone.** Shared models such as `User`, `Message`, `File` and `Conversation` now live in `SlackClient` as `Components.Schemas.<Name>`, with a top-level alias of the same name (`User` is `Components.Schemas.User`).
- **Web API and events share one set of models.** An event's `Message` or `File` is the same type as a Web API response's.
- **Models describe every field the Java SDK knows.** Fields that a single recorded sample happened to lack are now present. Across the 268 Web API responses, 467 top-level properties are new and one is gone.
- **Every property is optional except `ok` on responses and `type` on events.** Slack omits fields depending on the method, the object and the workspace.
- **Requests, method names and response names are unchanged.** `slack.client.chatPostMessage(body: .json(...))`, `.ok.body.json`, `Components.Schemas.ChatPostMessageResponse`, `MessageEvent` and the `Event` enum cases keep their names.

## Update dependencies and imports

Remove the `SlackModels` product from your package and replace `import SlackModels` with `import SlackClient`, or with `import SlackKit` in apps:

```swift
// Before
.product(name: "SlackKit", package: "swift-slack"),
.product(name: "SlackModels", package: "swift-slack"),

// After
.product(name: "SlackKit", package: "swift-slack"),
```

Replace `SlackModels.` prefixes with nothing (to use the top-level alias) or with `Components.Schemas.`:

```swift
// Before
func render(_ user: SlackModels.User) -> String

// After
func render(_ user: User) -> String
```

## Renamed types

Code that only reads properties through a response (`json.channels?.first?.name`) keeps working. Code that spells out a model type in its own signatures, stored properties or casts needs updating.

### Shared models

Forty former `SlackModels` names still exist with the same meaning, including `User`, `Message`, `File`, `Attachment`, `Team`, `Usergroup`, `BotProfile`, `Reaction`, `Reminder`, `Bookmark` and `Call`. The rest were inferred names that now map to the Java SDK's types:

| Before | After |
|---|---|
| `Channel` in `conversations.*` responses | `Conversation` |
| `ResponseMetadata` in 30 responses | `ErrorResponseMetadata` (or `WarningResponseMetadata`), whichever the Java SDK's response class uses; paginated responses keep `ResponseMetadata` with `nextCursor` |
| `FileElement`, `ItemFile` | `File` |
| `UserProfile` | `User.ProfilePayload` |
| `TeamProfile` | `TeamProfileGetResponse.ProfilePayload` |
| `Member` (`users.list`) | `User` |
| `Log` (`team.integrationLogs`) | `IntegrationLog` |
| `Comment` | `FileComment` |
| `Barrier` | `InformationBarrier` |
| `Item`, `Record`, `Subtask` (Lists) | `ListRecord` |
| `Files`, `Messages` (`search.*`) | `SearchResult` |
| `InviteElement` | `ConnectInvite` |
| `WorkflowConfiguration` | `WorkflowDraftConfiguration` or `WorkflowPublishedConfiguration` |
| `WorkflowStep` (`workflow_step_execute`) | `WorkflowStepExecution` |
| `APITestArgs` | `APITestResponse.ArgsPayload` |
| `Enterprise`, `Container` (interaction payloads) | unchanged names, now declared in `SlackApp` |

### Nested types

Objects that the Java SDK declares inside another class are nested types named after the property, with a `Payload` suffix. Array elements get the suffix twice.

```swift
// Before
let edited: SlackModels.Edited? = event.edited
let prefs: SlackModels.Prefs? = response.prefs

// After
let edited: MessageEvent.EditedPayload? = event.edited
let prefs: AdminConversationsGetConversationPrefsResponse.PrefsPayload? = response.prefs
let step: AppWorkflow.StepsPayloadPayload? = workflow.steps?.first
```

Prefer type inference or property chains (`response.prefs?.whoCanPost?.type`) to spelling these names out.

### Dictionaries

A JSON object with arbitrary keys becomes a struct whose values are in `additionalProperties`:

```swift
// Before
let input = workflow.steps?.first?.inputs?["message"]

// After
let input = workflow.steps?.first?.inputs?.additionalProperties["message"]
```

## Changed property types

| Property | Before | After |
|---|---|---|
| `File` image sizes (`originalW`, `thumb360W`, ...) | `String?` | `Int?` |
| `Message.type`, `Action.type`, `Bookmark.type` | `String` | `String?` |
| `ResponseMetadata.warnings` | `[OpenAPIValueContainer]?` | `[String]?` |
| `File.attachments` | `[OpenAPIValueContainer]?` | `[Attachment]?` |
| `Attachment.videoHtml` | `String?` | `AttachmentVideoHtml?` (see below) |
| `Attachment.videoHtmlWidth`, `videoHtmlHeight` | `Int?` | `Double?` |
| `MessageChangedEvent.previousMessage` | `Message?` | `MessageChangedEventPreviousMessage?` (see below) |

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

## Events

Event types are now aliases of `Components.Schemas` types declared in `SlackApp`, so `router.onEvent(MessageEvent.self)` and `switch event { case .message(let message): ... }` are unchanged. The events gained the fields the Java SDK declares and use the shared models (for example `MessageEvent.files` is `[File]?`). Event structs now have public memberwise initializers, which helps in tests.

Types that used to be shared but are event-specific in the Java SDK are now nested: `SlackModels.Item` becomes `ReactionAddedEvent.ItemPayload`, `SlackModels.DndStatus` becomes `DndUpdatedEvent.DndStatusPayload`, `SlackModels.MessageRoot` becomes `MessageThreadBroadcastEvent.RootPayload`, and so on.

## Block Kit

- `Block`, `View` and the element enums (`ActionElementType`, `ContextElementType`, `SectionAccessory`, `InputElementType`, and the rich text element enums) gained `.unknown(type:payload:)`. A block or element type that SlackBlockKit does not model no longer fails the whole response. Exhaustive `switch` statements need a case for it.
- New types: `AlertBlock`, `CardBlock`, `CarouselBlock`, `ContextActionsBlock`, `FeedbackButtonsElement`, `IconButtonElement`, `URLInputElement`, `WorkflowButtonElement` and `FeedbackButtonObject`, with matching enum cases (`.alert`, `.card`, `.carousel`, `.contextActions`, `.workflowButton`, `.urlInput`).
- `MultiStaticSelectElement.options` is optional, and `optionGroups` is new.
- `TimePickerElement.timezone` is new.
- `ConversationFilterObject`, `TriggerObject` and `DispatchActionConfigurationObject` now read and write Slack's snake_case keys. Filters built by apps used keys that Slack ignored before.

## Known gaps

- `IMCreatedEvent.channel` is an untyped object, because the Java SDK has not modelled it yet.
- `Conversation` no longer has fields that only appeared in other methods' samples, such as `memberCount` and `isFrozen`. Admin APIs that return them have their own response types (`AdminConversationsSearchResponse`).
- `conversations.list` no longer exposes `callstack`, an internal debugging field.
