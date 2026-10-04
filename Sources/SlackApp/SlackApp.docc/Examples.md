# Practical Examples

Combine `SlackApp` routing with Block Kit views to build an interactive workflow.

## Interactive Task Management

This example lists tasks in response to a slash command, opens a modal when someone clicks a button in that message, and reads the modal's values on submission. It uses `SlackBlockKitDSL` for the views, so add that product to your target alongside `SlackKit`.

> Note: Events API handlers are acknowledged automatically. Slash command, interaction, shortcut, and view handlers must call `ack()`. Registering another handler for the same command, callback ID, or event type replaces the earlier one.

```swift
import SlackBlockKitDSL
import SlackKit

let router = Router()

// List the user's tasks
router.onSlashCommand("/tasks") { context, payload in
    try await context.ack()

    let tasks = try await TaskService.tasks(for: payload.userId)
    try await context.respond(
        to: payload.responseUrl,
        blocks: TaskListView(tasks: tasks).blocks,
        responseType: .ephemeral
    )
}

// Open the creation modal when the message's "Create Task" button is clicked.
// `onBlockAction(_:)` matches the button's action ID.
router.onBlockAction("create_task") { context, payload in
    try await context.ack()

    guard let triggerId = payload.triggerId else {
        return
    }

    try await context.client.viewsOpen(
        body: .json(.init(
            triggerId: triggerId,
            view: taskCreationModal().asView()
        ))
    )
}

// Handle the modal submission
router.onViewSubmission("create_task") { context, payload in
    let title = payload.view.state?["title_block", "task_title"]?.value ?? ""
    let priority = payload.view.state?["priority_block", "task_priority"]?.selectedOption?.value ?? "medium"

    let task = try await TaskService.createTask(title: title, priority: priority)

    let successView = Modal(title: Text("Task Created")) {
        Header { Text("Success! ✅") }

        Section {
            Text("Task *\(task.title)* has been created.")
                .type(.mrkdwn)
        }
    }
    .close(Text("Done"))

    try await context.ack(responseAction: .update, view: successView.asView())
}

func taskCreationModal() -> Modal {
    Modal(title: Text("New Task")) {
        Input("Title") {
            PlainTextInput("task_title")
                .placeholder("What needs to be done?")
        }
        .blockId("title_block")

        Input("Priority") {
            StaticSelect("task_priority") {
                Option("High").value("high")
                Option("Medium").value("medium")
                Option("Low").value("low")
            }
        }
        .blockId("priority_block")
    }
    .callbackId("create_task")
    .submit(Text("Create"))
}

struct TaskListView: SlackView {
    let tasks: [TaskItem]

    var blocks: [Block] {
        Header {
            Text("Your Tasks")
        }

        Actions {
            Button("Create Task")
                .actionId("create_task")
                .style(.primary)
        }

        Divider()

        if tasks.isEmpty {
            Section {
                Text("_No tasks found. Create your first task!_")
                    .type(.mrkdwn)
            }
        } else {
            for task in tasks {
                Section {
                    Text("*\(task.title)*")
                        .type(.mrkdwn)
                }
                .accessory(
                    Button("Open")
                        .actionId("open_task_\(task.id)")
                )
            }
        }
    }
}
```

`TaskService` and `TaskItem` stand in for your own storage layer.
