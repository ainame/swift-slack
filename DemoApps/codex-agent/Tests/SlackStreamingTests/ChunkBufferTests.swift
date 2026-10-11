@testable import SlackStreaming
import Testing

struct ChunkBufferTests {
    let task = TaskUpdate(id: "t1", title: "Fetch", status: .inProgress)

    @Test
    func `merges adjacent markdown and keeps tasks in order`() async {
        let buffer = ChunkBuffer()
        await buffer.append(.markdownText("Hel"))
        await buffer.append(.markdownText("lo"))
        await buffer.append(.taskUpdate(task))
        await buffer.append(.markdownText(" world"))

        let batch = await buffer.next()
        #expect(batch.chunks == [.markdownText("Hello"), .taskUpdate(task), .markdownText(" world")])
        #expect(!batch.isFinal)
    }

    @Test
    func `starts a new markdown chunk at the 12,000 character limit`() async {
        let buffer = ChunkBuffer()
        let half = String(repeating: "a", count: 6001)
        await buffer.append(.markdownText(half))
        await buffer.append(.markdownText(half))

        #expect(await buffer.next().chunks == [.markdownText(half), .markdownText(half)])
    }

    @Test
    func `marks the batch taken after finishing as final`() async {
        let buffer = ChunkBuffer()
        await buffer.append(.markdownText("last"))
        await buffer.finish()

        #expect(await buffer.next() == .init(chunks: [.markdownText("last")], isFinal: true))
        #expect(await buffer.next() == .init(chunks: [], isFinal: true))
    }

    @Test
    func `waits for the next chunk`() async {
        let buffer = ChunkBuffer()
        async let batch = buffer.next()
        await buffer.append(.markdownText("later"))

        #expect(await batch == .init(chunks: [.markdownText("later")], isFinal: false))
    }
}
