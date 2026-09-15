# ``SlackBlockKit``

Type-safe Swift API for Slack's Block Kit UI framework.

## Overview

SlackBlockKit provides a comprehensive, type-safe Swift interface to Slack's Block Kit framework. Block Kit is Slack's UI framework that allows you to create rich, interactive messages and modal interfaces using a system of components called "blocks."

This library provides Swift models for supported Block Kit components, with explicit mappings to Slack's JSON fields.

## Architecture

Block Kit applications are composed of these key elements:

- **Blocks**: The main structural components (sections, headers, actions, etc.)
- **Elements**: Interactive components (buttons, select menus, inputs)
- **Composition Objects**: Reusable objects (text, options, confirmation dialogs)
- **Views**: Top-level containers (modals, home tabs)

## Quick Start

```swift
import SlackBlockKit

// Create a welcome message with an action button
let welcomeSection = SectionBlock(
    text: TextObject(
        type: .mrkdwn,
        text: "*Welcome to our team!* Let's get you started."
    ),
    accessory: .button(ButtonElement(
        text: TextObject(text: "Get Started", type: .plainText),
        actionId: "get_started_button",
        style: .primary
    ))
)

let blocks: [Block] = [.section(welcomeSection)]
```

## Integration

SlackBlockKit integrates seamlessly with other swift-slack modules:

- Use with `SlackClient` to send messages and open modals
- Combine with `SlackBlockKitDSL` for declarative syntax
- Access shared types from `SlackModels`

```swift
import SlackClient
import SlackBlockKit

let slack = Slack(transport: transport, configuration: config)

try await slack.client.chatPostMessage(
    body: .json(.init(
        channel: "#general",
        blocks: blocks
    ))
)
```

## Containers and Task Cards

Use ``ContainerBlock`` to group child blocks and ``TaskCardBlock`` to display a task's status, rich-text details, output, and URL sources. Import `SlackBlockKitDSL` to build container children with a result builder:

```swift
import SlackBlockKit
import SlackBlockKitDSL

let tasks = ContainerBlock(title: "Tasks", isCollapsible: true) {
    TaskCardBlock(
        taskId: "task_1",
        title: "Collecting results",
        status: "in_progress"
    )
}

let blocks: [Block] = [tasks.render()]
```

## Topics

### Getting Started

- <doc:BlockKit>

### Block Types

- ``Block``
- ``SectionBlock``
- ``HeaderBlock``
- ``ActionsBlock``
- ``InputBlock``
- ``ContextBlock``
- ``DividerBlock``
- ``ImageBlock``
- ``RichTextBlock``
- ``VideoBlock``
- ``FileBlock``
- ``MarkdownBlock``
- ``ContainerBlock``
- ``TaskCardBlock``

### Source Elements

- ``URLSourceElement``

### Interactive Elements

- ``ButtonElement``
- ``StaticSelectElement``
- ``ExternalSelectElement``
- ``UsersSelectElement``
- ``ChannelsSelectElement``
- ``ConversationsSelectElement``
- ``PlainTextInputElement``
- ``NumberInputElement``
- ``EmailInputElement``
- ``DatePickerElement``
- ``TimePickerElement``
- ``CheckboxesElement``
- ``RadioButtonsElement``

### Composition Objects

- ``TextObject``
- ``OptionObject``
- ``OptionGroupObject``
- ``ConfirmationDialogObject``
- ``DispatchActionConfigurationObject``
- ``ConversationFilterObject``
- ``SlackIconObject``

### Views

- ``View``
- ``ModalView``
- ``HomeTabView``

### Element Types

- ``ActionElementType``
- ``InputElementType``
- ``ContextElementType``
- ``SectionAccessory``

## See Also

- [Slack Block Kit Reference](https://api.slack.com/block-kit)
