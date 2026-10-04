# ``SlackBlockKitDSL``

SwiftUI-inspired declarative syntax for building Slack Block Kit interfaces.

## Overview

SlackBlockKitDSL provides a modern, declarative API for building Slack Block Kit interfaces. Inspired by SwiftUI, it uses result builders and method chaining to create clean, readable code while maintaining the full power of Slack's Block Kit framework.

The DSL transforms verbose Block Kit JSON structures into intuitive Swift code, making it easier to build, maintain, and understand complex Slack interfaces.

## Quick Comparison

**SlackBlockKit:**
```swift
import SlackBlockKit

let welcome = SectionBlock(
    text: TextObject(
        type: .mrkdwn,
        text: "*Welcome!* Click the button to get started."
    ),
    accessory: .button(ButtonElement(
        text: TextObject(type: .plainText, text: "Get Started"),
        actionId: "get_started",
        style: .primary
    ))
)
```

**SlackBlockKitDSL:**
```swift
import SlackBlockKitDSL

let welcome = Section {
    Text("*Welcome!* Click the button to get started.")
        .type(.mrkdwn)
}
.accessory(
    Button("Get Started")
        .actionId("get_started")
        .style(.primary)
)
```

## Quick Start

```swift
import SlackBlockKitDSL

// Create a reusable modal view
struct TaskCreationModal: SlackModalView {
    var title: TextObject { "Create Task" }
    var submit: TextObject? { "Create" }
    var callbackId: String? { "create_task" }

    var blocks: [Block] {
        Header {
            Text("Task Details")
        }
        
        Input("Title") {
            PlainTextInput("task_title")
                .placeholder("Enter task title")
        }
        
        Input("Priority") {
            StaticSelect("priority") {
                Option("High").value("high")
                Option("Medium").value("medium")
                Option("Low").value("low")
            }
        }
    }
}

// Open the modal with a trigger ID from a slash command or interaction
let modal = TaskCreationModal()
try await slack.client.viewsOpen(
    body: .json(.init(
        triggerId: triggerId,
        view: modal.render()
    ))
)
```

## Topics

### Getting Started

- <doc:BlockKitDSL>
- <doc:Examples>

### Core Components

- ``Text``
- ``Section``
- ``Header``
- ``Actions``
- ``Input``
- ``Divider``
- ``Context``

### Interactive Elements

- ``Button``
- ``StaticSelect``
- ``UsersSelect``
- ``ChannelsSelect``
- ``ConversationsSelect``
- ``ExternalSelect``
- ``PlainTextInput``
- ``NumberInput``
- ``EmailInput``
- ``DatePicker``
- ``TimePicker``
- ``Checkboxes``
- ``RadioButtons``

### Composition Objects

- ``Option``
- ``OptionGroup``
- ``ConfirmationDialog``
- ``DispatchActionConfig``

### Rich Content

- ``RichText``
- ``RichSection``
- ``RichList``
- ``RichTextContent``
- ``RichEmoji``
- ``RichLink``
- ``RichUser``
- ``RichChannel``
- ``Image``
- ``Video``

### Views and Containers

- ``Modal``
- ``HomeTab``
- ``SlackView``
- ``SlackModalView``
- ``SlackHomeTabView``

### Result Builders

- ``BlockBuilder``
- ``ActionElementBuilder``
- ``ContextElementBuilder``
- ``TextBuilder``
- ``TextListBuilder``
- ``OptionBuilder``
- ``OptionGroupBuilder``
- ``InputElementBuilder``
- ``MarkdownBuilder``

### Protocols

- ``BlockComponent``
- ``ViewConvertible``
- ``ActionElementConvertible``
- ``InputElementConvertible``
- ``SectionAccessoryConvertible``

## Architecture

The DSL is built on several key concepts:

### Result Builders

Swift's result builders enable declarative syntax:

```swift
Modal(title: Text("Settings")) {
    Header { Text("Configuration") }
    
    Section { Text("General settings") }
    
    if showAdvanced {
        Section { Text("Advanced options") }
    }
    
    Actions {
        Button("Save").actionId("save")
        Button("Cancel").actionId("cancel")
    }
}
```

### Method Chaining

Fluent interface for component configuration:

```swift
Button("Submit")
    .actionId("submit_form")
    .style(.primary)
    .confirm(ConfirmationDialog(
        title: Text("Confirm"),
        text: Text("Submit the form?")
    ))
```

### Protocol-Based Views

Reusable components with SwiftUI-like patterns:

```swift
struct UserProfile: SlackModalView {
    let user: User
    
    var title: TextObject { "User Profile" }
    
    var blocks: [Block] {
        Header { Text(user.name) }
        Section { Text(user.email) }
        // ... more blocks
    }
}
```

## Integration

SlackBlockKitDSL builds on top of SlackBlockKit and integrates with the entire swift-slack ecosystem:

```swift
import SlackBlockKitDSL
import SlackKit

// Open a modal from a SlackApp handler
router.onSlashCommand("/create-task") { context, payload in
    try await context.ack()
    try await context.client.viewsOpen(
        body: .json(.init(
            triggerId: payload.triggerId,
            view: TaskCreationModal().render()
        ))
    )
}

// Post blocks with the Web API client
let blocks: [Block] = [
    Header { Text("Status Update") }.render(),
    Section { Text("Deployment successful! ✅") }.render(),
]

try await slack.client.chatPostMessage(
    body: .json(.init(
        blocks: blocks,
        channel: "#deployments"
    ))
)
```

## Migration from SlackBlockKit

The DSL provides a smooth migration path from direct SlackBlockKit usage:

```swift
// Before: SlackBlockKit
let modelSection = SectionBlock(
    text: TextObject(type: .mrkdwn, text: "*Status:* Active"),
    accessory: .button(ButtonElement(
        text: TextObject(type: .plainText, text: "Details"),
        actionId: "view_details",
        style: .primary
    ))
)

// After: SlackBlockKitDSL
let dslSection = Section {
    Text("*Status:* Active").type(.mrkdwn)
}
.accessory(
    Button("Details")
        .actionId("view_details")
        .style(.primary)
)
```

