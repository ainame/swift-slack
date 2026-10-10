import SlackBlockKit
import SlackBlockKitDSL

enum SimpleExamples {
    /// Simple modal with minimal configuration
    struct SimpleGreetingModal: SlackModalView {
        var title: TextObject = "Hello World"

        var blocks: [Block] {
            Section {
                Text("Welcome to Slack!")
            }
        }
    }

    /// More complex modal with all the bells and whistles
    struct FeedbackModal: SlackModalView {
        let userName: String

        var title: TextObject {
            "Feedback Form"
        }

        var submit: TextObject? {
            "Submit Feedback"
        }

        var close: TextObject? {
            "Cancel"
        }

        var callbackId: String {
            "feedback_form"
        }

        var notifyOnClose: Bool? {
            true
        }

        var blocks: [Block] {
            Section {
                Text("Hi \(userName), we'd love to hear your feedback!")
                    .type(.mrkdwn)
            }

            Input(
                element: {
                    PlainTextInput()
                        .actionId("feedback_text")
                        .multiline(true)
                        .placeholder(Text("Type your feedback here..."))
                },
                label: {
                    Text("Your Feedback")
                },
            )

            Input(
                element: {
                    StaticSelect {
                        Option("Very Satisfied").value("5")
                        Option("Satisfied").value("4")
                        Option("Neutral").value("3")
                        Option("Dissatisfied").value("2")
                        Option("Very Dissatisfied").value("1")
                    }
                    .actionId("satisfaction_rating")
                    .placeholder(Text("Select rating"))
                },
                label: {
                    Text("How satisfied are you?")
                },
            )
        }
    }

    /// Simple home tab
    struct WelcomeHomeTab: SlackHomeTabView {
        let userName: String

        var blocks: [Block] {
            Header {
                Text("Welcome, \(userName)!")
            }

            Section {
                Text("Here's what's happening today:")
            }

            Divider()

            Section {
                Text("📅 3 meetings scheduled")
                Text("📧 12 new messages")
                Text("✅ 5 tasks completed")
            }

            Actions {
                Button("View Calendar")
                    .actionId("view_calendar")
                    .style(.primary)

                Button("Check Messages")
                    .actionId("check_messages")
            }
        }
    }

    /// Usage
    static func demonstrateSimpleUsage() {
        // Simple modal
        let greeting = SimpleGreetingModal()
        let view = greeting.render()
        switch view {
        case let .modal(greetingModal):
            print("Modal title: \(greetingModal.title.text)")
        case .homeTab, .unknown:
            break
        }

        // Complex modal
        let feedback = FeedbackModal(userName: "Alice")
        let view2 = feedback.render()

        switch view2 {
        case let .modal(feedbackModal):
            print("Modal has submit button: \(feedbackModal.submit != nil)")
        case .homeTab, .unknown:
            break
        }

        // Home tab
        let home = WelcomeHomeTab(userName: "Bob")
        let view3 = home.render()

        switch view3 {
        case .modal, .unknown:
            break
        case let .homeTab(homeTab):
            print("Home tab has \(homeTab.blocks.count) blocks")
        }
    }
}
