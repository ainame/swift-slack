import Foundation
import SlackBlockKit
import SlackBlockKitDSL
import Testing

struct ContainerAndTaskCardTests {
    @Test func `build new blocks`() throws {
        let url = try #require(URL(string: "https://example.com/task"))
        let task = TaskCardBlock(
            taskId: "task_1", title: "Working", status: "in_progress",
            sources: [URLSourceElement(url: url, text: "task")],
            icon: SlackIconObject(name: "check"), hideTitle: true,
        )
        let container = ContainerBlock(
            title: "Tasks", subtitle: "Current work", width: "wide",
            isCollapsible: true, defaultCollapsed: false, hasHeaderDivider: true,
            blockId: "tasks",
        ) {
            task
        }
        #expect(container.childBlocks == [.taskCard(task)])
        #expect(container.title?.text == "Tasks")
        #expect(container.subtitle?.text == "Current work")
        #expect(container.width == "wide")
        #expect(container.isCollapsible == true)
        #expect(container.defaultCollapsed == false)
        #expect(container.hasHeaderDivider == true)
        #expect(container.blockId == "tasks")
        @BlockBuilder func content() -> [Block] {
            container
            task
        }
        #expect(content() == [.container(container), .taskCard(task)])

        let encoded = try JSONEncoder().encode(content())
        let decoded = try JSONDecoder().decode([Block].self, from: encoded)
        #expect(decoded == content())
    }
}
