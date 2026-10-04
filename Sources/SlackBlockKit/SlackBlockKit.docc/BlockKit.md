# Building Rich Interfaces with SlackBlockKit

Create complex, interactive Slack interfaces using Block Kit components.

## Overview

SlackBlockKit provides a comprehensive, type-safe Swift interface to Slack's Block Kit framework. Block Kit is Slack's UI framework that allows you to create rich, interactive messages and modal interfaces using a system of components called "blocks."

This module gives you direct access to all Block Kit components with full control over their properties and structure, matching Slack's JSON Block Kit specification exactly.

## Block Kit Fundamentals

Block Kit applications are composed of these key elements:

- **Blocks**: The main structural components (sections, headers, actions, etc.)
- **Elements**: Interactive components (buttons, select menus, inputs)
- **Composition Objects**: Reusable objects (text, options, confirmation dialogs)

### Core Building Blocks

```swift
import SlackBlockKit

// Text objects for content
let welcomeText = TextObject(
    type: .mrkdwn,
    text: "*Welcome to our team!* Let's get you started."
)

// Section block with text and accessory
let welcomeSection = SectionBlock(
    text: welcomeText,
    accessory: .button(ButtonElement(
        text: TextObject(type: .plainText, text: "Get Started"),
        actionId: "get_started_button",
        style: .primary
    ))
)

// Header block
let headerBlock = HeaderBlock(
    text: TextObject(type: .plainText, text: "Team Onboarding")
)

// Combine into a message
let blocks: [Block] = [
    .header(headerBlock),
    .section(welcomeSection)
]
```

## Block Types

SlackBlockKit supports all Block Kit block types:

### Layout Blocks

**SectionBlock**: Display text and an optional accessory element
```swift
SectionBlock(
    text: TextObject(type: .mrkdwn, text: "Task *completed* ✅"),
    accessory: .button(ButtonElement(
        text: TextObject(type: .plainText, text: "View Details"),
        actionId: "view_details"
    ))
)
```

**HeaderBlock**: Large text for section headers
```swift
HeaderBlock(
    text: TextObject(type: .plainText, text: "Project Status")
)
```

**DividerBlock**: Visual separator
```swift
DividerBlock()
```

**ActionsBlock**: Container for interactive elements
```swift
ActionsBlock(elements: [
    .button(ButtonElement(
        text: TextObject(type: .plainText, text: "Approve"),
        actionId: "approve",
        style: .primary
    )),
    .button(ButtonElement(
        text: TextObject(type: .plainText, text: "Reject"),
        actionId: "reject",
        style: .danger
    ))
])
```

**ContextBlock**: Supplementary information
```swift
ContextBlock(elements: [
    .text(TextObject(type: .mrkdwn, text: "Last updated: 2 hours ago"))
])
```

### Input Blocks

**InputBlock**: Form inputs with labels
```swift
InputBlock(
    label: TextObject(type: .plainText, text: "Email Address"),
    element: .plainTextInput(PlainTextInputElement(
        actionId: "email_input",
        placeholder: TextObject(type: .plainText, text: "Enter your email")
    ))
)
```

### Rich Content Blocks

**ImageBlock**: Display images
```swift
ImageBlock(
    altText: "Team photo",
    imageUrl: URL(string: "https://example.com/team.jpg")!,
    title: TextObject(type: .plainText, text: "Our Amazing Team")
)
```

**RichTextBlock**: Complex formatted content with lists, quotes, and styling
```swift
RichTextBlock(elements: [
    .section(RichTextSection(elements: [
        .text(RichTextTextElement(
            text: "Important: ",
            style: RichTextTextStyle(bold: true)
        )),
        .text(RichTextTextElement(text: "Please review the attached document."))
    ]))
])
```

## Interactive Elements

### Buttons

Create interactive buttons with various styles:

```swift
// Primary action button
ButtonElement(
    text: TextObject(type: .plainText, text: "Submit"),
    actionId: "submit_form",
    style: .primary
)

// Danger button with confirmation
ButtonElement(
    text: TextObject(type: .plainText, text: "Delete"),
    actionId: "delete_item",
    style: .danger,
    confirm: ConfirmationDialogObject(
        title: TextObject(type: .plainText, text: "Delete Item"),
        text: TextObject(type: .plainText, text: "Are you sure you want to delete this item?"),
        confirm: TextObject(type: .plainText, text: "Delete"),
        deny: TextObject(type: .plainText, text: "Cancel")
    )
)
```

### Select Menus

Various types of select menus for different data sources:

```swift
// Static options
StaticSelectElement(
    options: [
        OptionObject(
            text: TextObject(type: .plainText, text: "High Priority"),
            value: "high"
        ),
        OptionObject(
            text: TextObject(type: .plainText, text: "Medium Priority"),
            value: "medium"
        )
    ],
    actionId: "priority_select",
    placeholder: TextObject(type: .plainText, text: "Select priority")
)

// User selection
UsersSelectElement(
    actionId: "assignee_select",
    placeholder: TextObject(type: .plainText, text: "Assign to...")
)

// Channel selection
ChannelsSelectElement(
    actionId: "channel_select",
    placeholder: TextObject(type: .plainText, text: "Choose channel")
)
```

### Input Elements

**PlainTextInputElement**: Single or multi-line text input
```swift
PlainTextInputElement(
    actionId: "description_input",
    multiline: true,
    maxLength: 500,
    placeholder: TextObject(type: .plainText, text: "Enter description")
)
```

**CheckboxesElement**: Multiple choice selections
```swift
CheckboxesElement(
    options: [
        OptionObject(text: TextObject(type: .plainText, text: "Email notifications"), value: "email"),
        OptionObject(text: TextObject(type: .plainText, text: "SMS notifications"), value: "sms")
    ],
    actionId: "notification_preferences"
)
```

**DatePickerElement**: Date selection
```swift
DatePickerElement(
    actionId: "due_date",
    initialDate: "2023-12-01",
    placeholder: TextObject(type: .plainText, text: "Select due date")
)
```

## Composition Objects

### Text Objects

The foundation of all text content in Block Kit:

```swift
// Plain text (no formatting)
TextObject(type: .plainText, text: "Simple text content")

// Markdown text (supports formatting)
TextObject(type: .mrkdwn, text: "*Bold text* and _italic text_")

// Text with emoji control
TextObject(
    type: .plainText,
    text: "Text without emoji conversion",
    emoji: false
)
```

### Options and Option Groups

Structure choices for select menus and radio buttons:

```swift
// Individual option
OptionObject(
    text: TextObject(type: .plainText, text: "Option 1"),
    value: "opt1",
    description: TextObject(type: .plainText, text: "Description of option 1")
)

// Grouped options
OptionGroupObject(
    label: TextObject(type: .plainText, text: "Priority Levels"),
    options: [
        OptionObject(text: TextObject(type: .plainText, text: "High"), value: "high"),
        OptionObject(text: TextObject(type: .plainText, text: "Medium"), value: "medium"),
        OptionObject(text: TextObject(type: .plainText, text: "Low"), value: "low")
    ]
)
```

### Confirmation Dialogs

Add confirmation steps to destructive actions:

```swift
ConfirmationDialogObject(
    title: TextObject(type: .plainText, text: "Delete Project"),
    text: TextObject(type: .mrkdwn, text: "This will permanently delete the project and all associated data. This action cannot be undone."
    ),
    confirm: TextObject(type: .plainText, text: "Yes, Delete"),
    deny: TextObject(type: .plainText, text: "Cancel"),
    style: .danger
)
```

## Views

Block Kit views define the overall structure for modals and home tabs:

### Modal Views

```swift
ModalView(
    title: TextObject(type: .plainText, text: "Project Settings"),
    blocks: [
        .header(HeaderBlock(text: TextObject(type: .plainText, text: "Configuration"))),
        .input(InputBlock(
            label: TextObject(type: .plainText, text: "Project Name"),
            element: .plainTextInput(PlainTextInputElement(
                actionId: "project_name",
                initialValue: "My Project"
            ))
        ))
    ],
    close: TextObject(type: .plainText, text: "Cancel"),
    submit: TextObject(type: .plainText, text: "Save")
)
```

### Home Tab Views

```swift
HomeTabView(
    blocks: [
        .header(HeaderBlock(text: TextObject(type: .plainText, text: "Welcome Dashboard"))),
        .section(SectionBlock(
            text: TextObject(type: .mrkdwn, text: "Your recent activity:")
        ))
    ]
)
```

## Integration with SlackClient

Use these Block Kit components with SlackClient's Web API:

```swift
import SlackClient
import SlackBlockKit

let blocks: [Block] = [
    .header(HeaderBlock(text: TextObject(type: .plainText, text: "Notification"))),
    .section(SectionBlock(
        text: TextObject(type: .mrkdwn, text: "Your deployment was successful! ✅")
    ))
]

try await slack.client.chatPostMessage(
    body: .json(.init(
        blocks: blocks,
        channel: "#deployments"
    ))
)
```
