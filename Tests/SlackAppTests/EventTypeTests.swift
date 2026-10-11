#if Events
import Foundation
@testable import SlackApp
import Testing

struct EventTests {
    // MARK: - Regular Message Tests

    @Test
    func `regular message without subtype`() throws {
        let json = """
        {
            "type": "message",
            "channel": "C1234567890",
            "user": "U1234567890",
            "text": "Hello, world!",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Should decode as regular message
        if case let .message(event) = eventType {
            #expect(event.text == "Hello, world!")
            #expect(event.channel == "C1234567890")
            #expect(event.user == "U1234567890")
        } else {
            Issue.record("Expected .message case, got \(eventType)")
        }
    }

    // MARK: - Known Subtype Tests

    @Test
    func `bot message`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "bot_message",
            "channel": "C1234567890",
            "text": "Bot says hello",
            "bot_id": "B1234567890",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Should decode as bot message
        if case let .messageBot(event) = eventType {
            #expect(event.text == "Bot says hello")
            #expect(event.botId == "B1234567890")
        } else {
            Issue.record("Expected .messageBot case, got \(eventType)")
        }
    }

    @Test
    func `message changed`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "message_changed",
            "channel": "C1234567890",
            "ts": "1234567890.123456",
            "message": {
                "type": "message",
                "user": "U1234567890",
                "text": "Updated message",
                "ts": "1234567890.123450"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Should decode as message changed
        if case .messageChanged = eventType {
            // Success
        } else {
            Issue.record("Expected .messageChanged case, got \(eventType)")
        }
    }

    @Test
    func `channel join message`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "channel_join",
            "channel": "C1234567890",
            "user": "U1234567890",
            "text": "<@U1234567890> has joined the channel",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Should decode as channel join message
        if case .messageChannelJoin = eventType {
            // Success
        } else {
            Issue.record("Expected .messageChannelJoin case, got \(eventType)")
        }
    }

    // MARK: - Unknown Subtype Tests

    @Test
    func `unknown subtype`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "new_experimental_subtype",
            "channel": "C1234567890",
            "text": "Some new message type",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Should decode as unsupported with type and subtype
        if case let .unsupported(typeInfo) = eventType {
            #expect(typeInfo == "message - new_experimental_subtype")
        } else {
            Issue.record("Expected .unsupported case with 'message - new_experimental_subtype', got \(eventType)")
        }
    }

    @Test
    func `empty subtype`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "",
            "channel": "C1234567890",
            "text": "Message with empty subtype",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // Empty subtype should be treated as unknown
        if case let .unsupported(typeInfo) = eventType {
            #expect(typeInfo == "message - ")
        } else {
            Issue.record("Expected .unsupported case with 'message - ', got \(eventType)")
        }
    }

    // MARK: - Edge Case Tests

    @Test
    func `message with null subtype`() throws {
        let json = """
        {
            "type": "message",
            "subtype": null,
            "channel": "C1234567890",
            "text": "Message with null subtype",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        // null subtype should be treated as no subtype
        if case let .message(event) = eventType {
            #expect(event.text == "Message with null subtype")
        } else {
            Issue.record("Expected .message case for null subtype, got \(eventType)")
        }
    }

    @Test
    func `message with invalid subtype type`() throws {
        let json = """
        {
            "type": "message",
            "subtype": 123,
            "channel": "C1234567890",
            "text": "Message with numeric subtype",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()

        // Should throw an error because subtype is not a string
        #expect(throws: Error.self) {
            _ = try decoder.decode(Event.self, from: json)
        }
    }

    // MARK: - Multiple Subtype Tests

    @Test
    func `all message subtypes`() throws {
        let subtypeTests: [(subtype: String, expectedCase: String)] = [
            ("bot_message", "messageBot"),
            ("message_changed", "messageChanged"),
            ("message_deleted", "messageDeleted"),
            ("channel_archive", "messageChannelArchive"),
            ("channel_join", "messageChannelJoin"),
            ("channel_leave", "messageChannelLeave"),
            ("channel_name", "messageChannelName"),
            ("channel_purpose", "messageChannelPurpose"),
            ("channel_topic", "messageChannelTopic"),
            ("channel_unarchive", "messageChannelUnarchive"),
            ("channel_posting_permissions", "messageChannelPostingPermissions"),
            ("file_share", "messageFileShare"),
            ("me_message", "messageMe"),
            ("message_replied", "messageReplied"),
            ("thread_broadcast", "messageThreadBroadcast"),
            ("ekm_access_denied", "messageEkmAccessDenied"),
            ("group_topic", "messageGroupTopic"),
        ]

        for (subtype, expectedCase) in subtypeTests {
            let json = """
            {
                "type": "message",
                "subtype": "\(subtype)",
                "channel": "C1234567890",
                "ts": "1234567890.123456"
            }
            """.data(using: .utf8)!

            let decoder = JSONDecoder()
            let eventType = try decoder.decode(Event.self, from: json)

            // Verify it's not unsupported
            if case .unsupported = eventType {
                Issue.record("Subtype '\(subtype)' decoded as unsupported, expected \(expectedCase)")
            }

            // For more specific testing, you'd check each case individually
            // This is a simple check that it's not unsupported
        }
    }

    // MARK: - Payload Extraction Tests

    @Test
    func `message payload extraction`() throws {
        let json = """
        {
            "type": "message",
            "channel": "C1234567890",
            "user": "U1234567890",
            "text": "Test message",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        let payload = eventType.payload
        #expect(payload != nil)

        if let messageEvent = payload as? MessageEvent {
            #expect(messageEvent.text == "Test message")
        } else {
            Issue.record("Expected payload to be MessageEvent")
        }
    }

    @Test
    func `unsupported payload extraction`() throws {
        let json = """
        {
            "type": "message",
            "subtype": "future_subtype",
            "channel": "C1234567890",
            "ts": "1234567890.123456"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let eventType = try decoder.decode(Event.self, from: json)

        let payload = eventType.payload
        #expect(payload == nil)
    }

    // MARK: - Equality and Hashing Tests

    @Test
    func `events compare by case and payload`() throws {
        func decode(_ json: String) throws -> Event {
            try JSONDecoder().decode(Event.self, from: Data(json.utf8))
        }
        let message = try decode(#"{ "type": "message", "channel": "C1", "text": "hi", "ts": "1.1" }"#)
        let sameMessage = try decode(#"{ "type": "message", "channel": "C1", "text": "hi", "ts": "1.1" }"#)
        let otherMessage = try decode(#"{ "type": "message", "channel": "C1", "text": "bye", "ts": "1.1" }"#)
        let meMessage = try decode(#"{ "type": "message", "subtype": "me_message", "channel": "C1", "text": "hi", "ts": "1.1" }"#)
        let unsupported = try decode(#"{ "type": "future_event" }"#)

        #expect(message == sameMessage)
        #expect(message.hashValue == sameMessage.hashValue)
        #expect(message != otherMessage)
        #expect(message != meMessage)
        #expect(message != unsupported)
        #expect(unsupported == .unsupported("future_event"))
        #expect(unsupported.hashValue == Event.unsupported("future_event").hashValue)
        #expect(unsupported != .unsupported("other_event"))
        #expect(Set([message, sameMessage, otherMessage, unsupported]).count == 3)
    }
}
#endif
