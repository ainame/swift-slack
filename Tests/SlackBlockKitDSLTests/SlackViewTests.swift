import Foundation
import SlackBlockKit
@testable import SlackBlockKitDSL
import Testing

struct SlackViewTests {
    /// Test native for-in loop
    @Test func `native for in loop`() {
        struct TestView: SlackView {
            let items = ["Apple", "Banana", "Orange"]

            var blocks: [Block] {
                Header { Text("Fruit List") }

                // Using native for-in loop
                for item in items {
                    Section {
                        Text(item)
                    }
                }
            }
        }

        let view = TestView()
        let blocks = view.blocks

        #expect(blocks.count == 4) // 1 header + 3 sections

        // Check header
        if case let .header(header) = blocks[0] {
            #expect(header.text.text == "Fruit List")
        } else {
            Issue.record("First block should be header")
        }

        // Check sections
        let expectedFruits = ["Apple", "Banana", "Orange"]
        for (index, fruit) in expectedFruits.enumerated() {
            if case let .section(section) = blocks[index + 1] {
                #expect(section.text?.text == fruit)
            } else {
                Issue.record("Block at index \(index + 1) should be section")
            }
        }
    }

    /// Test enumerated for-in loop
    @Test func `enumerated for in loop`() {
        struct TestView: SlackView {
            let items = ["First", "Second", "Third"]

            var blocks: [Block] {
                Header { Text("Numbered List") }

                // Using enumerated
                for (index, item) in items.enumerated() {
                    Section {
                        Text("\(index + 1). \(item)")
                    }
                }
            }
        }

        let view = TestView()
        let blocks = view.blocks

        #expect(blocks.count == 4)

        // Check sections have correct numbering
        let expectedTexts = ["1. First", "2. Second", "3. Third"]
        for (index, expectedText) in expectedTexts.enumerated() {
            if case let .section(section) = blocks[index + 1] {
                #expect(section.text?.text == expectedText)
            } else {
                Issue.record("Block at index \(index + 1) should be section")
            }
        }
    }

    /// Test complex scenario with conditionals inside loops
    @Test func `for in with conditionals`() {
        struct TestView: SlackView {
            let numbers = [1, 2, 3, 4, 5]

            var blocks: [Block] {
                Header { Text("Even Numbers") }

                for number in numbers {
                    if number % 2 == 0 {
                        Section {
                            Text("Even: \(number)")
                        }
                    }
                }
            }
        }

        let view = TestView()
        let blocks = view.blocks

        #expect(blocks.count == 3) // 1 header + 2 even number sections

        // Check we only have even numbers
        if case let .section(section1) = blocks[1] {
            #expect(section1.text?.text == "Even: 2")
        } else {
            Issue.record("Second block should be section for 2")
        }

        if case let .section(section2) = blocks[2] {
            #expect(section2.text?.text == "Even: 4")
        } else {
            Issue.record("Third block should be section for 4")
        }
    }

    /// Test nested loops
    @Test func `nested for in loops`() {
        struct TestView: SlackView {
            let categories = [
                ("Fruits", ["Apple", "Banana"]),
                ("Vegetables", ["Carrot", "Broccoli"]),
            ]

            var blocks: [Block] {
                for (category, items) in categories {
                    Header { Text(category) }

                    for item in items {
                        Section {
                            Text("• \(item)")
                        }
                    }

                    Divider()
                }
            }
        }

        let view = TestView()
        let blocks = view.blocks

        // Should have: Header, 2 Sections, Divider, Header, 2 Sections, Divider = 8 blocks
        #expect(blocks.count == 8)

        // Verify structure
        #expect(blocks[0].isHeader)
        #expect(blocks[1].isSection)
        #expect(blocks[2].isSection)
        #expect(blocks[3].isDivider)
        #expect(blocks[4].isHeader)
        #expect(blocks[5].isSection)
        #expect(blocks[6].isSection)
        #expect(blocks[7].isDivider)
    }

    /// Test empty views and conditional rendering
    @Test func `empty and conditional rendering`() {
        struct TestView: SlackView {
            let showContent: Bool
            let items: [String]

            var blocks: [Block] {
                if showContent {
                    Header { Text("Items") }

                    if items.isEmpty {
                        Section {
                            Text("No items available")
                        }
                    } else {
                        for item in items {
                            Section {
                                Text(item)
                            }
                        }
                    }
                }
            }
        }

        // Test with no content
        let emptyView = TestView(showContent: false, items: [])
        #expect(emptyView.blocks.isEmpty)

        // Test with content but no items
        let noItemsView = TestView(showContent: true, items: [])
        #expect(noItemsView.blocks.count == 2) // Header + "No items" section

        // Test with content and items
        let fullView = TestView(showContent: true, items: ["Item 1", "Item 2"])
        #expect(fullView.blocks.count == 3) // Header + 2 item sections
    }

    /// Test with filter and map operations
    @Test func `filter and map operations`() {
        struct TestView: SlackView {
            let numbers = [1, 2, 3, 4, 5, 6]

            var blocks: [Block] {
                Header { Text("Even Numbers") }

                // Use filter and map instead of break/continue
                for number in numbers.filter({ $0 <= 4 && $0 % 2 == 0 }) {
                    Section {
                        Text("Number: \(number)")
                    }
                }
            }
        }

        let view = TestView()
        let blocks = view.blocks

        #expect(blocks.count == 3) // Header + sections for 2 and 4

        if case let .section(section1) = blocks[1] {
            #expect(section1.text?.text == "Number: 2")
        }

        if case let .section(section2) = blocks[2] {
            #expect(section2.text?.text == "Number: 4")
        }
    }

    /// Test SlackModalView protocol
    @Test func `modal view protocol`() {
        struct TestModal: SlackModalView {
            let userName: String

            var title: TextObject {
                TextObject(type: .plainText, text: "Hello \(userName)")
            }

            var submit: TextObject? {
                TextObject(type: .plainText, text: "Submit")
            }

            var callbackId: String? {
                "test_modal"
            }

            var blocks: [Block] {
                Section {
                    Text("Welcome message for \(userName)")
                }

                Actions {
                    Button("Action 1").actionId("action1")
                    Button("Action 2").actionId("action2")
                }
            }
        }

        let modal = TestModal(userName: "Alice")
        let view = modal.render()

        switch view {
        case let .modal(modalView):
            #expect(modalView.title.text == "Hello Alice")
            #expect(modalView.submit?.text == "Submit")
            #expect(modalView.callbackId == "test_modal")
            #expect(modalView.blocks.count == 2)

            // Verify blocks
            if case let .section(section) = modalView.blocks[0] {
                #expect(section.text?.text == "Welcome message for Alice")
            } else {
                Issue.record("First block should be section")
            }

            if case let .actions(actions) = modalView.blocks[1] {
                #expect(actions.elements.count == 2)
            } else {
                Issue.record("Second block should be actions")
            }
        case .homeTab:
            Issue.record("ModalView.render returns homeTab. This is a bug.")
        case .unknown:
            Issue.record("render() returns an unknown view. This is a bug.")
        }
    }

    /// Test SlackHomeTabView protocol
    @Test func `home tab view protocol`() {
        struct TestHomeTab: SlackHomeTabView {
            let items: [String]

            var externalId: String? {
                "test_home_tab"
            }

            var blocks: [Block] {
                Header {
                    Text("Home Tab")
                }

                for item in items {
                    Section {
                        Text(item)
                    }
                }
            }
        }

        let homeTab = TestHomeTab(items: ["Item 1", "Item 2"])
        let view = homeTab.render()
        switch view {
        case let .homeTab(homeTabView):
            #expect(homeTabView.externalId == "test_home_tab")
            #expect(homeTabView.blocks.count == 3) // 1 header + 2 sections

            if case let .header(header) = homeTabView.blocks[0] {
                #expect(header.text.text == "Home Tab")
            } else {
                Issue.record("First block should be header")
            }
        case .modal:
            Issue.record("HomeTabView.render() returns ModalView. This is a bug.")
        case .unknown:
            Issue.record("render() returns an unknown view. This is a bug.")
        }
    }

    /// Test minimal modal with defaults
    @Test func `minimal modal view`() {
        struct MinimalModal: SlackModalView {
            var title: TextObject {
                TextObject(type: .plainText, text: "Minimal Modal")
            }

            var blocks: [Block] {
                Section {
                    Text("Just a title and content")
                }
            }
        }

        let modal = MinimalModal()
        let view = modal.render()

        switch view {
        case let .modal(modalView):
            #expect(modalView.title.text == "Minimal Modal")
            #expect(modalView.submit == nil)
            #expect(modalView.close == nil)
            #expect(modalView.callbackId == nil)
            #expect(modalView.blocks.count == 1)
        case .homeTab:
            Issue.record("ModalView.render returns homeTab. This is a bug.")
        case .unknown:
            Issue.record("render() returns an unknown view. This is a bug.")
        }
    }
}

/// Helper extensions for cleaner assertions
extension Block {
    var isHeader: Bool {
        if case .header = self { return true }
        return false
    }

    var isSection: Bool {
        if case .section = self { return true }
        return false
    }

    var isDivider: Bool {
        if case .divider = self { return true }
        return false
    }
}
