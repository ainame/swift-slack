import Foundation
import SlackBlockKit
@testable import SlackBlockKitDSL
import Testing

/// Verifies that the DSL list result builders support `if`, `if let`, `if/else`, `switch`, and `for`.
///
/// Most tests build the same component with control flow and with the equivalent flat
/// list of children, then compare the rendered Block Kit values. The explicit model tests
/// pin the builders' output to values assembled without the builders under test.
struct ResultBuilderControlFlowTests {
    private static let iconURL = URL(string: "https://example.com/icon.png")!

    // MARK: - BlockBuilder

    private func blocks(showDivider: Bool, title: String?, isUrgent: Bool, items: [String]) -> View {
        HomeTab {
            Header { Text("Tasks") }
            if showDivider {
                Divider()
            }
            if let title {
                Section { Text(title) }
            }
            if isUrgent {
                Section { Text("Urgent") }
            } else {
                Section { Text("Normal") }
            }
            for item in items {
                Section { Text(item) }
            }
        }.asView()
    }

    @Test func `BlockBuilder supports control flow`() {
        #expect(blocks(showDivider: false, title: nil, isUrgent: false, items: []) == HomeTab {
            Header { Text("Tasks") }
            Section { Text("Normal") }
        }.asView())

        #expect(blocks(showDivider: true, title: "Title", isUrgent: true, items: ["a", "b"]) == HomeTab {
            Header { Text("Tasks") }
            Divider()
            Section { Text("Title") }
            Section { Text("Urgent") }
            Section { Text("a") }
            Section { Text("b") }
        }.asView())
    }

    // MARK: - ContextElementBuilder

    private func context(showIcon: Bool, assignee: String?, isDone: Bool, attendees: [String]) -> Block {
        Context {
            Text("Created by someone")
            if showIcon {
                ContextImage(imageUrl: Self.iconURL, altText: "icon")
            }
            if let assignee {
                Text("Assigned to <@\(assignee)>")
            }
            if isDone {
                Text("Done")
            } else {
                Text("Open")
            }
            for attendee in attendees {
                Text("<@\(attendee)>")
            }
        }.render()
    }

    @Test func `ContextElementBuilder supports control flow`() {
        #expect(context(showIcon: false, assignee: nil, isDone: false, attendees: []) == Context {
            Text("Created by someone")
            Text("Open")
        }.render())

        #expect(context(showIcon: true, assignee: "U1", isDone: true, attendees: ["U2", "U3"]) == Context {
            Text("Created by someone")
            ContextImage(imageUrl: Self.iconURL, altText: "icon")
            Text("Assigned to <@U1>")
            Text("Done")
            Text("<@U2>")
            Text("<@U3>")
        }.render())
    }

    @Test func `ContextElementBuilder supports a body that is only a for loop`() {
        let attendees = ["U1", "U2"]
        #expect(Context {
            for attendee in attendees {
                Text("<@\(attendee)>")
            }
        }.render() == Context {
            Text("<@U1>")
            Text("<@U2>")
        }.render())
    }

    // MARK: - ActionElementBuilder

    private func actions(showCancel: Bool, deleteId: String?, isEditing: Bool, extras: [String]) -> Block {
        Actions {
            Button("OK").actionId("ok")
            if showCancel {
                Button("Cancel").actionId("cancel")
            }
            if let deleteId {
                Button("Delete").actionId(deleteId)
            }
            if isEditing {
                Button("Save").actionId("save")
            } else {
                Button("Edit").actionId("edit")
            }
            for extra in extras {
                Button(extra).actionId(extra)
            }
        }.render()
    }

    @Test func `ActionElementBuilder supports control flow`() {
        #expect(actions(showCancel: false, deleteId: nil, isEditing: false, extras: []) == Actions {
            Button("OK").actionId("ok")
            Button("Edit").actionId("edit")
        }.render())

        #expect(actions(showCancel: true, deleteId: "delete", isEditing: true, extras: ["x", "y"]) == Actions {
            Button("OK").actionId("ok")
            Button("Cancel").actionId("cancel")
            Button("Delete").actionId("delete")
            Button("Save").actionId("save")
            Button("x").actionId("x")
            Button("y").actionId("y")
        }.render())
    }

    // MARK: - TextListBuilder

    private func section(showSubtitle: Bool, note: String?, isPublic: Bool, tags: [String]) -> Block {
        Section {
            Text("Title")
            if showSubtitle {
                Text("Subtitle")
            }
            if let note {
                Text(note)
            }
            if isPublic {
                Text("Public")
            } else {
                Text("Private")
            }
            for tag in tags {
                Text(tag)
            }
        }.render()
    }

    @Test func `TextListBuilder supports control flow`() {
        #expect(section(showSubtitle: false, note: nil, isPublic: false, tags: []) == Section {
            Text("Title")
            Text("Private")
        }.render())

        #expect(section(showSubtitle: true, note: "Note", isPublic: true, tags: ["a", "b"]) == Section {
            Text("Title")
            Text("Subtitle")
            Text("Note")
            Text("Public")
            Text("a")
            Text("b")
        }.render())
    }

    // MARK: - OptionBuilder

    private func options(showOther: Bool, custom: String?, isAdmin: Bool, extras: [String]) -> ActionElementType {
        StaticSelect("select") {
            Option("Default").value("default")
            if showOther {
                Option("Other").value("other")
            }
            if let custom {
                Option(custom).value(custom)
            }
            if isAdmin {
                Option("Admin").value("admin")
            } else {
                Option("Member").value("member")
            }
            for extra in extras {
                Option(extra).value(extra)
            }
        }.asActionElement()
    }

    @Test func `OptionBuilder supports control flow`() {
        #expect(options(showOther: false, custom: nil, isAdmin: false, extras: []) == StaticSelect("select") {
            Option("Default").value("default")
            Option("Member").value("member")
        }.asActionElement())

        #expect(options(showOther: true, custom: "c", isAdmin: true, extras: ["x", "y"]) == StaticSelect("select") {
            Option("Default").value("default")
            Option("Other").value("other")
            Option("c").value("c")
            Option("Admin").value("admin")
            Option("x").value("x")
            Option("y").value("y")
        }.asActionElement())
    }

    // MARK: - OptionGroupBuilder

    private func optionGroups(showArchived: Bool, recent: String?, isAdmin: Bool, teams: [String]) -> ActionElementType {
        StaticSelect {
            OptionGroup(label: "Active") { Option("A").value("a") }
            if showArchived {
                OptionGroup(label: "Archived") { Option("Z").value("z") }
            }
            if let recent {
                OptionGroup(label: "Recent") { Option(recent).value(recent) }
            }
            if isAdmin {
                OptionGroup(label: "Admin") { Option("Admin").value("admin") }
            } else {
                OptionGroup(label: "Member") { Option("Member").value("member") }
            }
            for team in teams {
                OptionGroup(label: team) { Option(team).value(team) }
            }
        }.asActionElement()
    }

    @Test func `OptionGroupBuilder supports control flow`() {
        #expect(optionGroups(showArchived: false, recent: nil, isAdmin: false, teams: []) == StaticSelect {
            OptionGroup(label: "Active") { Option("A").value("a") }
            OptionGroup(label: "Member") { Option("Member").value("member") }
        }.asActionElement())

        #expect(optionGroups(showArchived: true, recent: "r", isAdmin: true, teams: ["t1", "t2"]) == StaticSelect {
            OptionGroup(label: "Active") { Option("A").value("a") }
            OptionGroup(label: "Archived") { Option("Z").value("z") }
            OptionGroup(label: "Recent") { Option("r").value("r") }
            OptionGroup(label: "Admin") { Option("Admin").value("admin") }
            OptionGroup(label: "t1") { Option("t1").value("t1") }
            OptionGroup(label: "t2") { Option("t2").value("t2") }
        }.asActionElement())
    }

    // MARK: - RichTextElementBuilder

    private func richText(showQuote: Bool, author: String?, isCode: Bool, notes: [String]) -> Block {
        RichText {
            RichSection { RichTextContent("note") }
            if showQuote {
                RichQuote { RichTextContent("quote") }
            }
            if let author {
                RichSection { RichUser(author) }
            }
            if isCode {
                RichPreformatted { RichTextContent("code") }
            } else {
                RichList { RichSection { RichTextContent("item") } }
            }
            for note in notes {
                RichSection { RichTextContent(note) }
            }
        }.render()
    }

    @Test func `RichTextElementBuilder supports control flow`() {
        #expect(richText(showQuote: false, author: nil, isCode: false, notes: []) == RichText {
            RichSection { RichTextContent("note") }
            RichList { RichSection { RichTextContent("item") } }
        }.render())

        #expect(richText(showQuote: true, author: "U1", isCode: true, notes: ["a", "b"]) == RichText {
            RichSection { RichTextContent("note") }
            RichQuote { RichTextContent("quote") }
            RichSection { RichUser("U1") }
            RichPreformatted { RichTextContent("code") }
            RichSection { RichTextContent("a") }
            RichSection { RichTextContent("b") }
        }.render())
    }

    // MARK: - RichTextSectionBuilder

    private func richList(showSecond: Bool, owner: String?, isDone: Bool, items: [String]) -> Block {
        RichText {
            RichList {
                RichSection { RichTextContent("first") }
                if showSecond {
                    RichSection { RichTextContent("second") }
                }
                if let owner {
                    RichSection { RichUser(owner) }
                }
                if isDone {
                    RichSection { RichEmoji("white_check_mark") }
                } else {
                    RichSection { RichEmoji("hourglass") }
                }
                for item in items {
                    RichSection { RichTextContent(item) }
                }
            }
        }.render()
    }

    @Test func `RichTextSectionBuilder supports control flow`() {
        #expect(richList(showSecond: false, owner: nil, isDone: false, items: []) == RichText {
            RichList {
                RichSection { RichTextContent("first") }
                RichSection { RichEmoji("hourglass") }
            }
        }.render())

        #expect(richList(showSecond: true, owner: "U1", isDone: true, items: ["a", "b"]) == RichText {
            RichList {
                RichSection { RichTextContent("first") }
                RichSection { RichTextContent("second") }
                RichSection { RichUser("U1") }
                RichSection { RichEmoji("white_check_mark") }
                RichSection { RichTextContent("a") }
                RichSection { RichTextContent("b") }
            }
        }.render())
    }

    // MARK: - RichTextContentBuilder

    private func richContent(showEmoji: Bool, channel: String?, isBold: Bool, users: [String]) -> Block {
        RichText {
            RichSection {
                RichTextContent("Hello")
                if showEmoji {
                    RichEmoji("wave")
                }
                if let channel {
                    RichChannel(channel)
                }
                if isBold {
                    RichTextContent("bold", bold: true)
                } else {
                    RichTextContent("plain")
                }
                for user in users {
                    RichUser(user)
                }
            }
            RichQuote {
                if let channel {
                    RichChannel(channel)
                }
            }
            RichPreformatted {
                for user in users {
                    RichTextContent(user, code: true)
                }
            }
        }.render()
    }

    @Test func `RichTextContentBuilder supports control flow`() {
        #expect(richContent(showEmoji: false, channel: nil, isBold: false, users: []) == RichText {
            RichSection {
                RichTextContent("Hello")
                RichTextContent("plain")
            }
            RichQuote {}
            RichPreformatted {}
        }.render())

        #expect(richContent(showEmoji: true, channel: "C1", isBold: true, users: ["U1", "U2"]) == RichText {
            RichSection {
                RichTextContent("Hello")
                RichEmoji("wave")
                RichChannel("C1")
                RichTextContent("bold", bold: true)
                RichUser("U1")
                RichUser("U2")
            }
            RichQuote {
                RichChannel("C1")
            }
            RichPreformatted {
                RichTextContent("U1", code: true)
                RichTextContent("U2", code: true)
            }
        }.render())
    }

    // MARK: - MarkdownBuilder

    private func markdown(showIntro: Bool, footer: String?, isDone: Bool, items: [String]) -> Block {
        Markdown {
            "# Report"
            if showIntro {
                "Intro"
            }
            if let footer {
                footer
            }
            if isDone {
                "Status: done"
            } else {
                "Status: open"
            }
            for item in items {
                "- \(item)"
            }
        }.render()
    }

    @Test func `MarkdownBuilder supports control flow`() {
        #expect(markdown(showIntro: false, footer: nil, isDone: false, items: []) == Markdown("# Report\nStatus: open").render())

        #expect(
            markdown(showIntro: true, footer: "Footer", isDone: true, items: ["a", "b"])
                == Markdown("# Report\nIntro\nFooter\nStatus: done\n- a\n- b").render(),
        )
    }

    // MARK: - Explicit model values

    private enum Priority {
        case low
        case medium
        case high
    }

    @Test(arguments: [Priority.low, .medium, .high])
    private func `ContextElementBuilder flattens switch and for into explicit elements`(priority: Priority) {
        let attendees = ["U1", "U2"]
        let block = Context {
            Text("Status")
            switch priority {
            case .low:
                Text("low")
            case .medium:
                ContextImage(imageUrl: Self.iconURL, altText: "medium")
            case .high:
                Text("high")
                Text("urgent")
            }
            for attendee in attendees {
                Text(attendee)
            }
        }.render()

        let priorityElements: [ContextElementType] = switch priority {
        case .low:
            [.text(Text("low").render())]
        case .medium:
            [ContextImage(imageUrl: Self.iconURL, altText: "medium").asContextElement()]
        case .high:
            [.text(Text("high").render()), .text(Text("urgent").render())]
        }
        let expected: [ContextElementType] = [.text(Text("Status").render())]
            + priorityElements
            + [.text(Text("U1").render()), .text(Text("U2").render())]
        #expect(block == .context(ContextBlock(elements: expected, blockId: nil)))
    }

    @Test func `rich text builders flatten control flow into explicit elements`() {
        let items = ["a", "b"]
        let author: String? = "U1"
        let priority = Priority.medium
        let block = RichText {
            RichSection {
                RichTextContent("note")
                if let author {
                    RichUser(author)
                }
                switch priority {
                case .low, .high:
                    RichEmoji("red_circle")
                case .medium:
                    RichEmoji("large_yellow_circle")
                    RichTextContent("medium")
                }
            }
            RichList {
                for item in items {
                    RichSection { RichTextContent(item) }
                }
            }
            switch priority {
            case .low, .high:
                RichPreformatted { RichTextContent("code") }
            case .medium:
                RichQuote {
                    for item in items {
                        RichTextContent(item)
                    }
                }
            }
        }.render()

        let a = RichTextContent("a").asRichTextContent()
        let b = RichTextContent("b").asRichTextContent()
        #expect(block == .richText(RichTextBlock(
            elements: [
                .section(RichTextSection(elements: [
                    RichTextContent("note").asRichTextContent(),
                    RichUser("U1").asRichTextContent(),
                    RichEmoji("large_yellow_circle").asRichTextContent(),
                    RichTextContent("medium").asRichTextContent(),
                ])),
                .list(RichTextList(
                    style: .bullet,
                    elements: [RichTextSection(elements: [a]), RichTextSection(elements: [b])],
                    indent: nil,
                )),
                .quote(RichTextQuote(elements: [a, b], border: nil)),
            ],
            blockId: nil,
        )))
    }

    @Test func `OptionGroupBuilder flattens control flow into explicit groups`() {
        let teams = ["t1", "t2"]
        let priority = Priority.low
        let element = StaticSelect {
            switch priority {
            case .low:
                OptionGroup(label: "Low") { Option("L").value("l") }
            case .medium, .high:
                OptionGroup(label: "Other") { Option("O").value("o") }
            }
            for team in teams {
                OptionGroup(label: team) { Option(team).value(team) }
            }
        }.asActionElement()

        guard case let .staticSelect(select) = element else {
            Issue.record("Expected a static select, got \(element)")
            return
        }
        #expect(select.options == nil)
        #expect(select.optionGroups == [
            OptionGroup(label: "Low") { Option("L").value("l") }.render(),
            OptionGroup(label: "t1") { Option("t1").value("t1") }.render(),
            OptionGroup(label: "t2") { Option("t2").value("t2") }.render(),
        ])
    }

    @Test func `MarkdownBuilder keeps explicit blank lines and supports switch`() {
        let priority = Priority.high
        let block = Markdown {
            "# Report"
            ""
            switch priority {
            case .low:
                "Low"
            case .medium, .high:
                "Needs attention"
            }
        }.render()

        #expect(block == Markdown("# Report\n\nNeeds attention").render())
    }
}
