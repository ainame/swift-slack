import SlackBlockKit
import SlackBlockKitDSL

enum FinalExamples {
    /// Simple modal example
    struct WelcomeModal: SlackModalView {
        let userName: String

        var title: TextObject = "Welcome!"

        var submit: TextObject? = "Get Started"

        var blocks: [Block] {
            Section {
                Text("Hi \(userName), welcome to our workspace!")
            }

            Actions {
                Button("View Tutorial")
                    .actionId("tutorial")
                    .style(.primary)
            }
        }
    }

    /// Home tab example
    struct DashboardHomeTab: SlackHomeTabView {
        let stats: DashboardStats

        struct DashboardStats {
            let messages: Int
            let files: Int
            let meetings: Int
        }

        var blocks: [Block] {
            Header {
                Text("📊 Your Dashboard")
            }

            Section {
                Text("*Today's Activity*")
                    .type(.mrkdwn)
                Text("Messages: \(stats.messages)")
                Text("Files shared: \(stats.files)")
                Text("Meetings: \(stats.meetings)")
            }
        }
    }

    /// Usage example
    static func demonstrateAPI() {
        // Modal usage
        let modal = WelcomeModal(userName: "Alice")
        let view = modal.render() // Clean API
        switch view {
        case let .modal(modalView):
            print("Modal title: \(modalView.title.text)")
        case .homeTab, .unknown:
            break
        }

        // Home tab usage
        let stats = DashboardHomeTab.DashboardStats(
            messages: 42,
            files: 8,
            meetings: 3,
        )
        let homeTab = DashboardHomeTab(stats: stats)
        let view2 = homeTab.render() // Clean API

        switch view2 {
        case .modal, .unknown:
            break
        case let .homeTab(homeTabView):
            print("Home tab has \(homeTabView.blocks.count) blocks")
        }
    }
}
