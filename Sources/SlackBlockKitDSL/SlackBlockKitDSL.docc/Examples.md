# Practical Examples

Compose messages, modals, and App Home tabs with Block Kit.

## Overview

These examples show common Slack interface patterns built with `SlackBlockKitDSL`. The first example also shows the equivalent `SlackBlockKit` models for comparison.

Types such as `Project`, `Issue`, and `Meeting` stand in for your own app's data. For routing, acknowledgements, and responding to interactions, see the `SlackApp` documentation.

## Basic Message Examples

### Simple Welcome Message

A basic welcome message with formatted text and an action button.

**Using SlackBlockKitDSL:**
```swift
import SlackBlockKitDSL

let welcomeBlocks = [
    Header {
        Text("Welcome to the Team! 🎉")
    }.render(),
    
    Section {
        Text("We're excited to have you here. Let's get you started with your onboarding process.")
            .type(.mrkdwn)
    }.render(),
    
    Actions {
        Button("Start Onboarding")
            .actionId("start_onboarding")
            .style(.primary)
        
        Button("View Team Guide")
            .actionId("view_guide")
            .url(URL(string: "https://company.com/guide")!)
    }.render()
]
```

**Using SlackBlockKit:**
```swift
import SlackBlockKit

let welcomeBlocks: [Block] = [
    .header(HeaderBlock(
        text: TextObject(type: .plainText, text: "Welcome to the Team! 🎉")
    )),
    
    .section(SectionBlock(
        text: TextObject(
            type: .mrkdwn,
            text: "We're excited to have you here. Let's get you started with your onboarding process."
        )
    )),
    
    .actions(ActionsBlock(elements: [
        .button(ButtonElement(
            text: TextObject(type: .plainText, text: "Start Onboarding"),
            actionId: "start_onboarding",
            style: .primary
        )),
        .button(ButtonElement(
            text: TextObject(type: .plainText, text: "View Team Guide"),
            actionId: "view_guide",
            url: URL(string: "https://company.com/guide")!
        ))
    ]))
]
```

### Status Update with Context

A status update message showing project information with contextual details.

**Using SlackBlockKitDSL:**
```swift
let statusBlocks = [
    Section {
        Text("*Project Alpha* deployment completed successfully ✅")
            .type(.mrkdwn)
    }
    .accessory(
        Button("View Details")
            .actionId("view_deployment_details")
    ).render(),
    
    Context {
        Text("Deployed by Alice Johnson • <!date^1677123456^{date_short} at {time}|Mar 15, 2023 2:30 PM>")
            .type(.mrkdwn)
    }.render(),
    
    Divider().render(),
    
    Section {
        Text("*Deployment Summary:*")
            .type(.mrkdwn)
        Text("• 12 files updated")
        Text("• 0 breaking changes")
        Text("• 3.2s build time")
    }.render()
]
```

## Form and Modal Examples

### Task Creation Modal

A comprehensive task creation modal with various input types.

**Using SlackBlockKitDSL:**
```swift
struct TaskCreationModal: SlackModalView {
    let projectId: String
    
    var title: TextObject { "Create New Task" }
    
    var submit: TextObject? { "Create Task" }
    
    var callbackId: String? {
        "create_task_\(projectId)"
    }
    
    var blocks: [Block] {
        Header {
            Text("Task Information")
        }
        
        Input("Task Title") {
            PlainTextInput("task_title")
                .placeholder("Enter a descriptive title")
                .maxLength(100)
        }
        .hint("Keep it concise but descriptive")
        
        Input("Description") {
            PlainTextInput("task_description")
                .placeholder("Describe what needs to be done")
                .multiline(true)
                .maxLength(500)
        }
        .optional(true)
        
        Input("Priority") {
            StaticSelect("task_priority") {
                Option("🔴 High Priority").value("high")
                Option("🟡 Medium Priority").value("medium")
                Option("🟢 Low Priority").value("low")
            }
            .placeholder("Select priority level")
            .initialOption(Option("🟡 Medium Priority").value("medium"))
        }
        
        Input("Assignee") {
            UsersSelect("task_assignee")
                .placeholder("Assign to team member")
        }
        .optional(true)
        
        Input("Due Date") {
            DatePicker("due_date")
                .placeholder("Select due date")
        }
        .optional(true)
        
        Input("Labels") {
            Checkboxes {
                Option("Frontend").value("frontend")
                Option("Backend").value("backend")
                Option("Design").value("design")
                Option("Testing").value("testing")
                Option("Documentation").value("docs")
            }
            .actionId("task_labels")
        }
        .optional(true)
        .hint("Select all that apply")
        
        Divider()
        
        Context {
            Text("_All required fields must be completed before submitting_")
                .type(.mrkdwn)
        }
    }
}

// Usage
let modal = TaskCreationModal(projectId: "proj_123")
try await slack.client.viewsOpen(
    body: .json(.init(
        triggerId: triggerId,
        view: modal.render()
    ))
)
```

### Survey Form Modal

A customer feedback survey with various question types.

**Using SlackBlockKitDSL:**
```swift
struct FeedbackSurvey: SlackModalView {
    var title: TextObject { "Customer Feedback" }
    
    var submit: TextObject? { "Submit Feedback" }
    
    var blocks: [Block] {
        Header {
            Text("Help Us Improve")
        }
        
        Section {
            Text("Your feedback helps us build better products. This survey takes about 2 minutes.")
                .type(.mrkdwn)
        }
        
        Divider()
        
        Input("Overall Satisfaction") {
            RadioButtons {
                Option("😍 Extremely satisfied").value("5")
                Option("😊 Very satisfied").value("4")
                Option("😐 Somewhat satisfied").value("3")
                Option("😞 Not very satisfied").value("2")
                Option("😠 Not at all satisfied").value("1")
            }
            .actionId("satisfaction_rating")
        }
        
        Input("Which features do you use most?") {
            Checkboxes {
                Option("Project Management").value("projects")
                Option("Team Collaboration").value("collaboration")
                Option("File Sharing").value("files")
                Option("Notifications").value("notifications")
                Option("Integrations").value("integrations")
                Option("Reporting").value("reporting")
            }
            .actionId("used_features")
        }
        .optional(true)
        
        Input("How did you hear about us?") {
            StaticSelect {
                OptionGroup(label: "Online") {
                    Option("Google Search").value("google")
                    Option("Social Media").value("social")
                    Option("Online Ad").value("ad")
                }
                OptionGroup(label: "Referral") {
                    Option("Friend/Colleague").value("friend")
                    Option("Company Partner").value("partner")
                }
                OptionGroup(label: "Other") {
                    Option("Conference/Event").value("event")
                    Option("Blog/Article").value("blog")
                    Option("Other").value("other")
                }
            }
            .actionId("referral_source")
            .placeholder("Select one")
        }
        .optional(true)
        
        Input("Additional Comments") {
            PlainTextInput("additional_comments")
                .placeholder("Share any additional thoughts or suggestions")
                .multiline(true)
                .maxLength(1000)
        }
        .optional(true)
        
        Input("Contact Email") {
            EmailInput()
                .actionId("contact_email")
                .placeholder("your.email@company.com")
        }
        .optional(true)
        .hint("We'll only contact you if you'd like a follow-up")
        
        Divider()
        
        Context {
            Text("_Your responses are confidential and help us improve our service_")
                .type(.mrkdwn)
        }
    }
}
```

## Dashboard and List Examples

### Project Dashboard Home Tab

A comprehensive dashboard showing project status and quick actions.

**Using SlackBlockKitDSL:**
```swift
struct ProjectDashboard: SlackHomeTabView {
    let user: User
    let projects: [Project]
    let recentActivity: [Activity]
    
    var blocks: [Block] {
        Header {
            Text("Welcome back, \(user.displayName)! 👋")
        }
        
        Section {
            Text("*Your Projects*")
                .type(.mrkdwn)
        }
        .accessory(
            Button("Create Project")
                .actionId("create_project")
                .style(.primary)
        )
        
        // Project list
        for project in projects.prefix(5) {
            Section {
                Text("*\(project.name)*")
                    .type(.mrkdwn)
                Text("\(project.description)")
                Text("📊 \(project.completionPercentage)% complete • 👥 \(project.memberCount) members")
            }
            .accessory(
                Button("Open")
                    .actionId("open_project_\(project.id)")
            )
        }
        
        if projects.count > 5 {
            Context {
                Text("_Showing 5 of \(projects.count) projects_")
                    .type(.mrkdwn)
            }
            
            Actions {
                Button("View All Projects")
                    .actionId("view_all_projects")
            }
        }
        
        Divider()
        
        Section {
            Text("*Recent Activity*")
                .type(.mrkdwn)
        }
        
        // Activity feed
        for activity in recentActivity.prefix(3) {
            Section {
                Text("*\(activity.user.name)* \(activity.description)")
                    .type(.mrkdwn)
            }
            
            Context {
                Text("<!date^\(activity.timestamp)^{date_short} at {time}|Recently>")
                    .type(.mrkdwn)
            }
        }
        
        if recentActivity.count > 3 {
            Actions {
                Button("View Activity Feed")
                    .actionId("view_activity_feed")
            }
        }
        
        Divider()
        
        Section {
            Text("*Quick Actions*")
                .type(.mrkdwn)
        }
        
        Actions {
            Button("Create Task")
                .actionId("create_task")
                .style(.primary)
            
            Button("Schedule Meeting")
                .actionId("schedule_meeting")
            
            Button("View Reports")
                .actionId("view_reports")
        }
        
        Context {
            Text("Need help? Contact <@U123456> or visit our <https://help.company.com|help center>")
                .type(.mrkdwn)
        }
    }
}
```

### Issue Tracking List

A dynamic list of issues with filtering and actions.

**Using SlackBlockKitDSL:**
```swift
struct IssueTracker: SlackView {
    let issues: [Issue]
    let filter: IssueFilter
    
    var blocks: [Block] {
        Header {
            Text("Issue Tracker")
        }
        
        // Filter controls
        Section {
            Text("*Filter Issues*")
                .type(.mrkdwn)
        }
        
        Actions {
            StaticSelect("issue_status") {
                Option("All Issues").value("all")
                Option("Open").value("open")
                Option("In Progress").value("in_progress")
                Option("Resolved").value("resolved")
                Option("Closed").value("closed")
            }
            .placeholder("Filter by status")
            .initialOption(Option(filter.status.displayName).value(filter.status.rawValue))
            
            StaticSelect("issue_priority") {
                Option("All Priorities").value("all")
                Option("High").value("high")
                Option("Medium").value("medium")
                Option("Low").value("low")
            }
            .placeholder("Filter by priority")
            
            Button("Create Issue")
                .actionId("create_issue")
                .style(.primary)
        }
        
        Divider()
        
        if issues.isEmpty {
            Section {
                Text("_No issues found matching your filters._")
                    .type(.mrkdwn)
            }
            
            Actions {
                Button("Reset Filters")
                    .actionId("reset_filters")
                
                Button("Create First Issue")
                    .actionId("create_first_issue")
                    .style(.primary)
            }
        } else {
            // Issue list
            for issue in issues {
                Section {
                    Text("*#\(issue.number): \(issue.title)*")
                        .type(.mrkdwn)
                    Text(issue.description.prefix(100) + (issue.description.count > 100 ? "..." : ""))
                    Text("\(issue.priority.emoji) \(issue.priority.displayName) • \(issue.status.emoji) \(issue.status.displayName)")
                }
                .accessory(
                    Button("View")
                        .actionId("view_issue_\(issue.id)")
                )
                
                let assignment = issue.assignee.map { "Assigned to <@\($0)>" } ?? "Unassigned"
                Context {
                    Text("Created by <@\(issue.createdBy)> • <!date^\(issue.createdAt)^{date_short}|Recently>")
                        .type(.mrkdwn)
                    Text(assignment)
                        .type(.mrkdwn)
                }
                
                if issue != issues.last {
                    Divider()
                }
            }
            
            // Pagination
            if issues.count >= 10 {
                Actions {
                    Button("Load More")
                        .actionId("load_more_issues")
                }
            }
        }
        
        Context {
            Text("Showing \(issues.count) issues")
                .type(.mrkdwn)
        }
    }
}
```

## Rich Content Examples

### Announcement with Rich Formatting

A company announcement using rich text formatting.

**Using SlackBlockKitDSL:**
```swift
let announcementBlocks = [
    Header {
        Text("🎉 Company Update")
    }.render(),
    
    RichText {
        RichSection {
            RichTextContent("We're excited to announce that we've reached ", bold: false)
            RichTextContent("1 million users", bold: true)
            RichTextContent("! This milestone wouldn't have been possible without our amazing team.")
        }
        
        RichSection {
            RichTextContent("Here's what this means for us:")
        }
        
        RichList(style: .bullet) {
            RichSection {
                RichTextContent("Expanded engineering team by 50%")
            }
            RichSection {
                RichTextContent("New product features launching next quarter")
            }
            RichSection {
                RichTextContent("Additional investment in customer support")
            }
        }
        
        RichQuote {
            RichTextContent("This is just the beginning. We're building something truly special together.", italic: true)
            RichTextContent(" - CEO", bold: true)
        }
        
        RichSection {
            RichTextContent("Read the full announcement on our ")
            RichLink("https://company.com/blog/1m-users", text: "company blog")
            RichTextContent(".")
        }
    }.render(),
    
    Actions {
        Button("View Blog Post")
            .actionId("view_announcement")
            .url(URL(string: "https://company.com/blog/1m-users")!)
        
        Button("Share Feedback")
            .actionId("share_feedback")
            .style(.primary)
    }.render()
]
```

### Meeting Notes with Attendees

Structured meeting notes with participant information.

**Using SlackBlockKitDSL:**
```swift
struct MeetingNotes: SlackView {
    let meeting: Meeting
    let attendees: [User]
    let notes: [Note]
    let actionItems: [ActionItem]
    
    var blocks: [Block] {
        Header {
            Text("📝 \(meeting.title)")
        }
        
        Section {
            Text("*Date:* <!date^\(meeting.timestamp)^{date_long}|Meeting date>")
                .type(.mrkdwn)
            Text("*Duration:* \(meeting.duration) minutes")
            Text("*Location:* \(meeting.location)")
        }
        
        Section {
            Text("*Attendees (\(attendees.count)):*")
                .type(.mrkdwn)
        }
        
        Context {
            Text(attendees.map { "<@\($0.id)>" }.joined(separator: " "))
                .type(.mrkdwn)
        }
        
        Divider()
        
        Section {
            Text("*Meeting Notes*")
                .type(.mrkdwn)
        }
        
        for note in notes {
            if let author = note.author {
                RichText {
                    RichSection {
                        RichTextContent("• \(note.content) — ")
                        RichUser(author.id, italic: true)
                    }
                }
            } else {
                RichText {
                    RichSection {
                        RichTextContent("• \(note.content)")
                    }
                }
            }
        }
        
        if !actionItems.isEmpty {
            Divider()
            
            Section {
                Text("*Action Items*")
                    .type(.mrkdwn)
            }
            
            for item in actionItems {
                Section {
                    Text("☐ \(item.description)")
                        .type(.mrkdwn)
                }
                .accessory(
                    Button(item.isCompleted ? "✅ Done" : "Mark Done")
                        .actionId("complete_action_\(item.id)")
                )
                
                Context {
                    Text("Assigned to <@\(item.assigneeId)> • Due: <!date^\(item.dueDate)^{date_short}|TBD>")
                        .type(.mrkdwn)
                }
            }
        }
        
        Divider()
        
        Actions {
            Button("Edit Notes")
                .actionId("edit_meeting_notes")
            
            Button("Add Action Item")
                .actionId("add_action_item")
                .style(.primary)
            
            Button("Schedule Follow-up")
                .actionId("schedule_followup")
        }
    }
}
```
