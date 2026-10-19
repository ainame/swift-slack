import SlackBlockKit
@testable import SlackClient
import Testing

struct PartBufferTests {
    let task = StreamingMessage.TaskUpdate(id: "t1", title: "Fetch", status: .inProgress)

    @Test
    func `merges adjacent markdown and keeps tasks in order`() async {
        let buffer = PartBuffer()
        await buffer.append(.markdown("Hel"))
        await buffer.append(.markdown("lo"))
        await buffer.append(.task(task))
        await buffer.append(.markdown(" world"))

        let batch = await buffer.next()
        #expect(batch.parts == [.markdown("Hello"), .task(task), .markdown(" world")])
        #expect(!batch.isFinal)
    }

    @Test
    func `splits markdown at the 12,000 character limit`() async {
        let buffer = PartBuffer()
        await buffer.append(.markdown(String(repeating: "a", count: 7000)))
        await buffer.append(.markdown(String(repeating: "b", count: 18000)))

        #expect(await buffer.next().parts == [
            .markdown(String(repeating: "a", count: 7000) + String(repeating: "b", count: 5000)),
        ])
        #expect(await buffer.next().parts == [.markdown(String(repeating: "b", count: 12000))])
        #expect(await buffer.next().parts == [.markdown(String(repeating: "b", count: 1000))])
    }

    @Test
    func `counts emoji conservatively without losing unicode scalars`() async {
        let buffer = PartBuffer()
        let text = String(repeating: "😀", count: 8000)
        await buffer.append(.markdown(text))
        await buffer.finish(throwing: nil)
        let first = await buffer.next()
        let last = await buffer.next()
        #expect(first.parts == [.markdown(String(repeating: "😀", count: 6000))])
        #expect(last.parts == [.markdown(String(repeating: "😀", count: 2000))])
        #expect(!first.isFinal)
        #expect(last.isFinal)
    }

    @Test
    func `merges adjacent blocks up to 50 per chunk`() async {
        let buffer = PartBuffer()
        let divider = Block.divider(DividerBlock())
        await buffer.append(.blocks(Array(repeating: divider, count: 30)))
        await buffer.append(.blocks(Array(repeating: divider, count: 30)))

        #expect(await buffer.next().parts == [
            .blocks(Array(repeating: divider, count: 50)),
        ])
        #expect(await buffer.next().parts == [.blocks(Array(repeating: divider, count: 10))])
    }

    @Test
    func `bounds non-adjacent markdown and only marks the last request final`() async {
        let buffer = PartBuffer()
        await buffer.append(.markdown(String(repeating: "a", count: 8000)))
        await buffer.append(.task(task))
        await buffer.append(.markdown(String(repeating: "b", count: 8000)))
        await buffer.finish(throwing: nil)
        let first = await buffer.next()
        #expect(first.parts == [.markdown(String(repeating: "a", count: 8000)), .task(task)])
        #expect(!first.isFinal)
        let last = await buffer.next()
        #expect(last.parts == [.markdown(String(repeating: "b", count: 8000))])
        #expect(last.isFinal)
    }

    @Test
    func `marks the batch taken after finishing as final`() async {
        let buffer = PartBuffer()
        await buffer.append(.markdown("last"))
        await buffer.finish(throwing: nil)

        let batch = await buffer.next()
        #expect(batch.parts == [.markdown("last")])
        #expect(batch.isFinal)
        #expect(await buffer.next().parts.isEmpty)
    }

    @Test
    func `waits for the next part`() async {
        let buffer = PartBuffer()
        async let batch = buffer.next()
        await buffer.append(.markdown("later"))

        #expect(await batch.parts == [.markdown("later")])
    }

    @Test
    func `stops waiting when the sender is cancelled`() async {
        let buffer = PartBuffer()
        let waiting = Task { await buffer.next() }
        waiting.cancel()

        let batch = await waiting.value
        #expect(batch.parts.isEmpty)
        #expect(!batch.isFinal)
    }

    @Test
    func `refuses parts once closed`() async {
        let buffer = PartBuffer()
        await buffer.append(.markdown("kept"))

        #expect(await buffer.close().parts == [.markdown("kept")])
        #expect(await buffer.append(.markdown("dropped")) == false)
    }
}
