@testable import CodexAgent
import Logging
import Testing

struct ChannelRegistryTests {
    @Test
    func `negative entries expire while positive channel identity stays known`() async {
        let slack = FakeSlack()
        let client = await slack.client()
        let channels = ChannelRegistry(negativeLifetime: .zero, logger: .init(label: "test"))
        await slack.channel(recordType: nil)
        #expect(await channels.kind(of: "C1", client: client) == .other)
        let origin = MessageLink(channel: "C0", ts: "1.0")
        await slack.channel(recordType: "agent_channel", origin: origin)
        #expect(await channels.kind(of: "C1", client: client) == .codeChannel(origin: origin))
        await slack.channel(recordType: nil)
        #expect(await channels.kind(of: "C1", client: client) == .codeChannel(origin: origin))
        #expect(await slack.requests("conversationsInfo").count == 2)
    }

    @Test
    func `negative entries are reused until they expire`() async {
        let slack = FakeSlack()
        let client = await slack.client()
        let channels = ChannelRegistry(logger: .init(label: "test"))
        await slack.channel(recordType: nil)
        #expect(await channels.kind(of: "C1", client: client) == .other)
        await slack.channel(recordType: "agent_channel")
        #expect(await channels.kind(of: "C1", client: client) == .other)
        #expect(await slack.requests("conversationsInfo").count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a stale channel lookup cannot erase a promoted Code channel or its origin`() async {
        let slack = FakeSlack()
        let client = await slack.client()
        let channels = ChannelRegistry(logger: .init(label: "test"))
        await slack.channel(recordType: nil)
        await slack.hold("conversationsInfo")
        let lookup = Task { await channels.kind(of: "C1", client: client) }
        await slack.waitFor("conversationsInfo")
        let origin = MessageLink(channel: "C0", ts: "1.0")
        channels.rememberCodeChannel("C1", origin: origin)
        await slack.release("conversationsInfo")
        #expect(await lookup.value == .codeChannel(origin: origin))
        #expect(await channels.kind(of: "C1", client: client) == .codeChannel(origin: origin))
        #expect(channels.origin(of: "C1") == origin)
        #expect(await slack.requests("conversationsInfo").count == 1)
    }

    @Test
    func `turns without an origin retain the link and an explicit link replaces it`() {
        let channels = ChannelRegistry(logger: .init(label: "test"))
        let first = MessageLink(channel: "C0", ts: "1.0")
        let updated = MessageLink(channel: "C2", ts: "2.0")
        channels.rememberCodeChannel("C1", origin: first)
        channels.rememberCodeChannel("C1", origin: nil)
        #expect(channels.origin(of: "C1") == first)
        channels.rememberCodeChannel("C1", origin: updated)
        #expect(channels.origin(of: "C1") == updated)
        #expect(channels.stopScope(channel: "C1", threadTs: "1.0").threadTs == nil)
    }

    @Test
    func `unknown channel stops retain thread scope without looking up Slack`() {
        let channels = ChannelRegistry(logger: .init(label: "test"))
        #expect(channels.stopScope(channel: "C1", threadTs: "1.0").threadTs == "1.0")
        #expect(channels.stopScope(channel: "C1", threadTs: "").threadTs == nil)
        #expect(channels.stopScope(channel: "C1", threadTs: nil).threadTs == nil)
        #expect(!channels.isCodeChannel("C1"))
    }
}
