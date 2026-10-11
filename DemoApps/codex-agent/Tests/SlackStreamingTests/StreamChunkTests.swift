import Foundation
@testable import SlackStreaming
import Testing

struct StreamChunkTests {
    @Test
    func `encodes a markdown_text chunk`() throws {
        #expect(try json(.markdownText("**Hi**")) == ["type": "markdown_text", "text": "**Hi**"])
    }

    @Test
    func `encodes a task_update chunk without absent fields`() throws {
        let chunk = StreamChunk.taskUpdate(TaskUpdate(id: "t1", title: "Fetch", status: .inProgress))
        #expect(try json(chunk) == ["type": "task_update", "id": "t1", "title": "Fetch", "status": "in_progress"])
    }

    @Test
    func `truncates task_update fields to 256 characters`() throws {
        let long = String(repeating: "a", count: 300)
        let chunk = StreamChunk.taskUpdate(TaskUpdate(id: "t1", title: long, status: .complete, output: long))
        let object = try json(chunk)
        #expect(object["title"]?.count == 256)
        #expect(object["output"]?.count == 256)
        #expect(object["title"]?.hasSuffix("…") == true)
    }

    @Test
    func `encodes a plan_update chunk`() throws {
        #expect(try json(.planUpdate(title: "Plan")) == ["type": "plan_update", "title": "Plan"])
    }

    @Test
    func `converts chunks to the generated container, or nil when empty`() throws {
        #expect(try StreamChunk.container(for: []) == nil)
        let container = try #require(try StreamChunk.container(for: [.markdownText("a"), .planUpdate(title: "b")]))
        #expect(container.value.count == 2)
    }

    private func json(_ chunk: StreamChunk) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(chunk))
    }
}
