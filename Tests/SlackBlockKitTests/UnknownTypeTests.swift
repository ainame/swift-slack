import Foundation
import OpenAPIRuntime
@testable import SlackBlockKit
import Testing

private func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func roundTrip<T: Codable>(_ type: T.Type, _ json: String) throws -> (T, NSDictionary) {
    let value = try JSONDecoder().decode(T.self, from: Data(json.utf8))
    return try (value, jsonObject(JSONEncoder().encode(value)))
}

@Test
func `Unknown block type decodes as unknown and round-trips`() throws {
    let json = #"{"type":"future_block","block_id":"b1","nested":{"a":[1,2]}}"#
    let (block, encoded) = try roundTrip(Block.self, json)

    guard case let .unknown(type, payload) = block else {
        Issue.record("Expected .unknown, got \(block)")
        return
    }
    #expect(type == "future_block")
    #expect(payload.string(forKey: "block_id") == "b1")
    #expect(encoded == (try jsonObject(Data(json.utf8))))
}

@Test
func `Unknown element types decode as unknown and round-trip`() throws {
    let json = #"{"type":"future_element","action_id":"a1"}"#
    let expected = try jsonObject(Data(json.utf8))

    let (accessory, accessoryJSON) = try roundTrip(SectionAccessory.self, json)
    guard case .unknown("future_element", _) = accessory else { Issue.record("accessory: \(accessory)"); return }
    #expect(accessoryJSON == expected)

    let (context, contextJSON) = try roundTrip(ContextElementType.self, json)
    guard case .unknown("future_element", _) = context else { Issue.record("context: \(context)"); return }
    #expect(contextJSON == expected)

    let (action, actionJSON) = try roundTrip(ActionElementType.self, json)
    guard case .unknown("future_element", _) = action else { Issue.record("action: \(action)"); return }
    #expect(actionJSON == expected)

    let (input, inputJSON) = try roundTrip(InputElementType.self, json)
    guard case .unknown("future_element", _) = input else { Issue.record("input: \(input)"); return }
    #expect(inputJSON == expected)
}

@Test
func `Unknown rich text types decode as unknown and round-trip`() throws {
    let json = #"{"type":"rich_text_future","elements":[]}"#
    let expected = try jsonObject(Data(json.utf8))

    let (element, elementJSON) = try roundTrip(RichTextElementType.self, json)
    guard case .unknown("rich_text_future", _) = element else { Issue.record("element: \(element)"); return }
    #expect(elementJSON == expected)

    let contentJSON = #"{"type":"future_inline","value":"x"}"#
    let (content, contentEncoded) = try roundTrip(RichTextContentElement.self, contentJSON)
    guard case .unknown("future_inline", _) = content else { Issue.record("content: \(content)"); return }
    #expect(contentEncoded == (try jsonObject(Data(contentJSON.utf8))))
}

@Test
func `Unknown view type decodes as unknown and round-trips`() throws {
    let json = #"{"type":"agent","id":"V1","callback_id":"cb"}"#
    let (view, encoded) = try roundTrip(View.self, json)

    guard case .unknown("agent", _) = view else {
        Issue.record("Expected .unknown, got \(view)")
        return
    }
    #expect(view.id == "V1")
    #expect(view.callbackId == "cb")
    #expect(view.state == nil)
    #expect(encoded == (try jsonObject(Data(json.utf8))))
}

@Test
func `Known block types still decode to their cases`() throws {
    let block = try JSONDecoder().decode(Block.self, from: Data(#"{"type":"divider"}"#.utf8))
    guard case .divider = block else {
        Issue.record("Expected .divider, got \(block)")
        return
    }
}
