import Foundation
import OpenAPIRuntime
import SlackModels
import Testing

struct ContainerTests {
    @Test
    func `encode view container`() throws {
        let container = Container.view(.init(viewId: "V123"))
        let data = try JSONEncoder().encode(container)
        let decoded = try JSONDecoder().decode(OpenAPIObjectContainer.self, from: data)

        #expect(decoded.value["type"] as? String == "view")
        #expect(decoded.value["view_id"] as? String == "V123")
    }

    @Test
    func `decode view container`() throws {
        let json = """
        {
          "type": "view",
          "view_id": "V123"
        }
        """

        let container = try JSONDecoder().decode(Container.self, from: #require(json.data(using: .utf8)))

        #expect(container == .view(.init(viewId: "V123")))
        #expect(container._type == "view")
        #expect(container.viewId == "V123")
    }

    @Test
    func `decode message container`() throws {
        let json = """
        {
          "type": "message",
          "message_ts": "1606455372.001200",
          "channel_id": "C111",
          "is_ephemeral": true
        }
        """

        let container = try JSONDecoder().decode(Container.self, from: #require(json.data(using: .utf8)))

        #expect(container == .message(.init(
            messageTs: "1606455372.001200",
            channelId: "C111",
            isEphemeral: true,
        )))
        #expect(container._type == "message")
        #expect(container.messageTs == "1606455372.001200")
        #expect(container.channelId == "C111")
        #expect(container.isEphemeral == true)
    }

    @Test
    func `decode message attachment container`() throws {
        let json = """
        {
          "type": "message_attachment",
          "message_ts": "1661488735.191299",
          "attachment_id": 1,
          "channel_id": "C111",
          "is_ephemeral": false,
          "is_app_unfurl": true,
          "app_unfurl_url": "https://example.com/foo"
        }
        """

        let container = try JSONDecoder().decode(Container.self, from: #require(json.data(using: .utf8)))

        #expect(container == .messageAttachment(.init(
            messageTs: "1661488735.191299",
            channelId: "C111",
            attachmentId: 1,
            isEphemeral: false,
            isAppUnfurl: true,
            appUnfurlUrl: "https://example.com/foo",
            threadTs: nil,
            text: nil,
        )))
        #expect(container._type == "message_attachment")
        #expect(container.messageTs == "1661488735.191299")
        #expect(container.channelId == "C111")
        #expect(container.attachmentId == 1)
        #expect(container.isEphemeral == false)
    }

    @Test
    func `decode unknown container type`() throws {
        let json = """
        {
          "type": "canvas",
          "canvas_id": "CA123",
          "custom_flag": true
        }
        """

        let container = try JSONDecoder().decode(Container.self, from: #require(json.data(using: .utf8)))

        guard case let .unknown(type, payload) = container else {
            Issue.record("Expected unknown container")
            return
        }

        #expect(type == "canvas")
        #expect(container._type == "canvas")
        #expect(payload.value["canvas_id"] as? String == "CA123")
        #expect(payload.value["custom_flag"] as? Bool == true)
    }

    @Test
    func `encode unknown container type`() throws {
        let payload = try OpenAPIObjectContainer(unvalidatedValue: [
            "canvas_id": "CA123",
            "custom_flag": true,
        ])
        let container = Container.unknown(type: "canvas", payload: payload)

        let data = try JSONEncoder().encode(container)
        let decoded = try JSONDecoder().decode(OpenAPIObjectContainer.self, from: data)

        #expect(decoded.value["type"] as? String == "canvas")
        #expect(decoded.value["canvas_id"] as? String == "CA123")
        #expect(decoded.value["custom_flag"] as? Bool == true)
    }
}
