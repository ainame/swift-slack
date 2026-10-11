import Codex
@testable import CodexAgent
import Testing

struct NotificationTranslatorTests {
    @Test
    func `streams deltas and skips the completed copy of a streamed message`() {
        var translator = NotificationTranslator(turnID: "turn")
        let events = [
            translator.events(turnID: "turn", payload: delta("Hel", in: "m1")),
            translator.events(turnID: "turn", payload: delta("lo", in: "m1")),
            translator.events(turnID: "turn", payload: completed(message("Hello", id: "m1"))),
        ].flatMap(\.self)
        #expect(events == [.text("Hel"), .text("lo")])
    }

    @Test
    func `emits a message that arrives only as a completed item`() {
        var translator = NotificationTranslator(turnID: "turn")
        let events = [
            translator.events(turnID: "turn", payload: delta("Checking.", in: "m1")),
            translator.events(turnID: "turn", payload: completed(message("Which one?", id: "m2"))),
        ].flatMap(\.self)
        #expect(events == [.text("Checking."), .text("\n\nWhich one?")])
    }

    @Test
    func `ignores other turns`() {
        var translator = NotificationTranslator(turnID: "turn")
        #expect(translator.events(turnID: "other", payload: delta("x", in: "m1")).isEmpty)
    }

    private func delta(_ text: String, in itemID: String) -> CodexNotificationPayload {
        .agentMessageDelta(.init(delta: text, itemId: itemID, threadId: "thread", turnId: "turn"))
    }

    private func completed(_ item: ThreadItem) -> CodexNotificationPayload {
        .itemCompleted(.init(completedAtMs: 0, item: item, threadId: "thread", turnId: "turn"))
    }

    private func message(_ text: String, id: String) -> ThreadItem {
        .agentMessage(.init(id: id, phase: .finalAnswer, text: text, type: .agentMessage))
    }
}
