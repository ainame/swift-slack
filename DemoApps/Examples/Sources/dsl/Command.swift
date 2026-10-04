import Foundation
import SlackBlockKitDSL
import SlackKit

@main
struct Command {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["SLACK_OAUTH_TOKEN"],
              let appToken = ProcessInfo.processInfo.environment["SLACK_APP_LEVEL_TOKEN"] else {
            print("Prepare SLACK_OAUTH_TOKEN and SLACK_APP_LEVEL_TOKEN to run this script")
            exit(1)
        }

        let router = Router()

        // Handle global shortcuts
        router.onGlobalShortcut("run-something") { context, payload in
            try await context.ack()

            // Create a modal using the new SwiftUI-like DSL
            let view = Modal(
                title: Text("Welcome!"),
            ) {
                Header {
                    Text("Quick Form")
                }

                Section {
                    Text("Please fill out this quick form to continue.")
                }

                Divider()

                Input {
                    PlainTextInput()
                        .actionId("name_field")
                        .placeholder("Enter your name")
                } label: {
                    Text("Your Name")
                }

                Input {
                    StaticSelect {
                        Option("Red").value("red")
                        Option("Green").value("green")
                        Option("Blue").value("blue")
                    }
                    .actionId("color_select")
                    .placeholder(Text("Choose a color"))
                } label: {
                    Text("Favorite Color")
                }

                Input {
                    RadioButtons {
                        Option("Small").value("small")
                        Option("Medium").value("medium")
                        Option("Large").value("large")
                    }
                    .actionId("size_select")
                } label: {
                    Text("Size Preference")
                }

                Input {
                    Checkboxes {
                        Option("📧 Email notifications").value("email")
                        Option("📱 Push notifications").value("push")
                        Option("🔔 Desktop notifications").value("desktop")
                        Option("📊 Weekly reports").value("reports")
                    }
                    .actionId("notifications")
                } label: {
                    Text("Notification Preferences")
                }

                Input {
                    UsersSelect()
                        .actionId("manager_select")
                        .placeholder("Select your manager")
                } label: {
                    Text("Manager")
                }
                .optional(true)

                Input {
                    DatePicker()
                        .actionId("start_date")
                        .placeholder("Select start date")
                } label: {
                    Text("Start Date")
                }

                Actions {
                    Button("Cancel")
                        .actionId("cancel")
                        .style(.danger)

                    Button("Submit")
                        .actionId("submit")
                        .style(.primary)
                }
            }
            .submit(Text("Submit"))
            .callbackId("quick_form_modal")
            .asView()

            // Open the modal
            let response = try await context.client.viewsOpen(
                .init(body: .json(.init(
                    triggerId: payload.triggerId,
                    view: view,
                ))),
            )

            print("Modal opened: \(response)")
        }

        // Handle app home opened events
        router.onEvent(AppHomeOpenedEvent.self) { context, _, event in
            // Create a home tab view using the new DSL
            let view = HomeTab {
                Header {
                    Text("Welcome to the App Home! 🏠")
                }

                Section {
                    Text("Here's what you can do:")
                }
                .accessory(
                    Button("Get Started")
                        .actionId("get_started")
                        .style(.primary),
                )

                Divider()

                Section {
                    Text("*📊 View Analytics*\nCheck your team's performance").type(.mrkdwn)
                    Text("*📝 Create Reports*\nGenerate custom reports").type(.mrkdwn)
                    Text("*👥 Team Management*\nManage your team members").type(.mrkdwn)
                    Text("*⚙️ Settings*\nConfigure your preferences").type(.mrkdwn)
                }

                Actions {
                    Button("View Analytics")
                        .actionId("view_analytics")
                        .style(.primary)

                    Button("Create Report")
                        .actionId("create_report")

                    Button("Settings")
                        .actionId("settings")
                }

                Context {
                    Text("Last updated: just now")
                    ContextImage(
                        imageUrl: URL(string: "https://api.slack.com/img/blocks/bkb_template_images/appHomeNewUser.png")!,
                        altText: "App Home",
                    )
                }
            }
            .asView()

            // Publish the home tab
            let response = try await context.client.viewsPublish(
                .init(body: .json(.init(
                    userId: event.user ?? "",
                    view: view,
                ))),
            )

            print("Home tab published: \(response)")
        }

        // Handle any button in the quick form modal by the modal's callback ID
        router.onBlockAction(callbackId: "quick_form_modal") { context, payload in
            try await context.ack()

            // Create a success message modal
            let view = Modal(
                title: Text("Complete ✅"),
            ) {
                Header {
                    Text("Success! 🎉")
                }

                Section {
                    Text("Your form has been submitted successfully.").type(.plainText)
                }

                Divider()

                Section {
                    Text("*What happens next?*").type(.mrkdwn)
                    Text("• Your data has been saved").type(.mrkdwn)
                    Text("• You'll receive a confirmation email").type(.mrkdwn)
                    Text("• Our team will review your submission").type(.mrkdwn)
                }

                Actions {
                    Button("Done")
                        .actionId("done")
                        .style(.primary)
                        .confirm(
                            ConfirmationDialog(
                                title: Text("Are you sure?"),
                                text: Text("This will close the form."),
                                confirm: Text("Yes, close it"),
                                deny: Text("Cancel"),
                            ),
                        )
                }
            }
            .clearOnClose(true)
            .asView()

            // Update the view
            let response = try await context.client.viewsUpdate(
                .init(body: .json(.init(
                    viewId: payload.container.viewId,
                    view: view,
                ))),
            )

            print("View updated: \(response)")
        }

        // Handle button actions by action ID
        router.onBlockAction("done") { context, _ in
            try await context.ack()

            // Close the modal
            print("Done button clicked, closing modal")
        }

        // Handle additional interactive actions
        router.onBlockAction("get_started") { context, payload in
            try await context.ack()

            // Create an advanced form modal showcasing option groups
            let view = Modal(
                title: Text("Advanced Settings"),
            ) {
                Header {
                    Text("Configure Your Preferences")
                }

                Section {
                    Text("*Choose your preferred settings from the organized categories below.*").type(.mrkdwn)
                }

                Input {
                    StaticSelect {
                        OptionGroup(label: "Development") {
                            Option("🐍 Python").value("python")
                            Option("☕ Java").value("java")
                            Option("🦀 Rust").value("rust")
                            Option("🔷 TypeScript").value("typescript")
                        }
                        OptionGroup(label: "Design") {
                            Option("🎨 Figma").value("figma")
                            Option("✨ Sketch").value("sketch")
                            Option("🌈 Adobe XD").value("xd")
                        }
                        OptionGroup(label: "Management") {
                            Option("📊 Jira").value("jira")
                            Option("📝 Notion").value("notion")
                            Option("📋 Trello").value("trello")
                        }
                    }
                    .actionId("category_select")
                    .placeholder("Select from categories")
                } label: {
                    Text("Primary Tool")
                }

                Input {
                    ConversationsSelect()
                        .actionId("channel_select")
                        .placeholder("Select a channel")
                        .defaultToCurrentConversation(false)
                } label: {
                    Text("Default Channel")
                }

                Input {
                    NumberInput()
                        .actionId("hours_input")
                        .placeholder("Enter hours per week")
                        .minValue("1")
                        .maxValue("168")
                } label: {
                    Text("Work Hours Per Week")
                }

                Actions {
                    Button("Cancel")
                        .actionId("cancel_advanced")

                    Button("Save Settings")
                        .actionId("save_advanced")
                        .style(.primary)
                }
            }
            .callbackId("advanced_settings_modal")
            .asView()

            // Open the advanced modal
            let response = try await context.client.viewsOpen(
                .init(body: .json(.init(
                    triggerId: payload.triggerId,
                    view: view,
                ))),
            )

            print("Advanced modal opened: \(response)")
        }

        // This is demo so this doesn't automatically reconnect to socket when disconnected
        print("Starting Socket Mode connection...")
        let app = SlackApp(
            configuration: .init(
                userAgent: "SwiftBot",
                appToken: appToken,
                token: token,
            ),
            router: router,
            mode: .socketMode(options: []),
        )
        try await app.run()
    }
}
