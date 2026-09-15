import Foundation
import SlackBlockKit
import Testing

struct UpstreamBlockTests {
    // Ported from java-slack-sdk BlockKitTest at dbe498ce0.
    @Test(arguments: upstreamExamples)
    func `upstream payload round trip`(json: String) throws {
        let data = Data(json.utf8)
        let block = try JSONDecoder().decode(Block.self, from: data)
        let encoded = try JSONEncoder().encode(block)
        let original = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let result = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(original == result)
        #expect(try JSONDecoder().decode(Block.self, from: encoded) == block)
    }

    @Test func `nested container and task card`() throws {
        let richText = RichTextBlock(elements: [])
        let task = try TaskCardBlock(
            taskId: "task_42", title: "Processing data", status: "in_progress",
            details: richText, output: richText,
            sources: [URLSourceElement(url: #require(URL(string: "https://example.com")), text: "example")],
            blockId: "task", icon: SlackIconObject(name: "check"), hideTitle: true,
        )
        let block = Block.container(ContainerBlock(
            childBlocks: [.container(ContainerBlock(childBlocks: [.taskCard(task)]))],
        ))
        let data = try JSONEncoder().encode(block)
        #expect(try JSONDecoder().decode(Block.self, from: data) == block)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outer = try #require(json["child_blocks"] as? [[String: Any]])
        let inner = try #require(outer.first?["child_blocks"] as? [[String: Any]])
        let payload = try #require(inner.first)
        #expect(payload["task_id"] as? String == "task_42")
        #expect(payload["hide_title"] as? Bool == true)
        #expect(payload["block_id"] as? String == "task")
        #expect((payload["icon"] as? [String: String]) == ["type": "icon", "name": "check"])
        #expect(payload["details"] != nil)
        #expect(json["title"] == nil)
    }

    @Test func `container preserves every optional field`() throws {
        let block = try JSONDecoder().decode(Block.self, from: Data(Self.upstreamExamples[0].utf8))
        let container = try #require(Self.container(from: block))

        #expect(container.type == "container")
        #expect(container.blockId == "container1")
        #expect(container.title?.type == .plainText)
        #expect(container.title?.text == "Container Title")
        #expect(container.subtitle?.type == .mrkdwn)
        #expect(container.subtitle?.text == "*Bold* subtitle")
        #expect(container.width == "wide")
        #expect(container.isCollapsible == true)
        #expect(container.defaultCollapsed == false)
        #expect(container.hasHeaderDivider == nil)
        #expect(container.icon?.type == "image")
        #expect(container.icon?.altText == "icon")
        #expect(container.childBlocks.count == 2)
        #expect(container.childBlocks[0] == Block.section(SectionBlock(text: TextObject(type: .mrkdwn, text: "Section inside container."))))
        #expect(container.childBlocks[1] == Block.divider(DividerBlock()))
    }

    @Test func `container supports rich text title and header divider`() throws {
        let richTitleBlock = try JSONDecoder().decode(Block.self, from: Data(Self.upstreamExamples[1].utf8))
        let richTitleContainer = try #require(Self.container(from: richTitleBlock))
        #expect(richTitleContainer.title == nil)
        #expect(richTitleContainer.richTextTitle?.type == "rich_text")
        #expect(richTitleContainer.richTextTitle?.elements.count == 1)

        let dividerBlock = try JSONDecoder().decode(Block.self, from: Data(Self.upstreamExamples[2].utf8))
        let dividerContainer = try #require(Self.container(from: dividerBlock))
        #expect(dividerContainer.hasHeaderDivider == true)
        #expect(dividerContainer.isCollapsible == nil)
    }

    @Test func `task card exposes sources and rich text output`() throws {
        let block = try JSONDecoder().decode(Block.self, from: Data(Self.upstreamExamples[3].utf8))
        let taskCard = try #require(Self.taskCard(from: block))

        #expect(taskCard.type == "task_card")
        #expect(taskCard.taskId == "task_1")
        #expect(taskCard.title == "Fetching weather data")
        #expect(taskCard.status == "in_progress")
        #expect(taskCard.output?.type == "rich_text")
        #expect(taskCard.output?.elements.count == 1)
        let sources = try #require(taskCard.sources)
        #expect(sources.map(\.type) == ["url", "url"])
        #expect(sources.map(\.url.absoluteString) == ["https://weather.com/", "https://www.accuweather.com/"])
        #expect(sources.map(\.text) == ["weather.com", "accuweather.com"])
    }

    private static func container(from block: Block) -> ContainerBlock? {
        guard case let .container(value) = block else { return nil }
        return value
    }

    private static func taskCard(from block: Block) -> TaskCardBlock? {
        guard case let .taskCard(value) = block else { return nil }
        return value
    }

    private static let upstreamExamples = [
        #"""
        {
          "type": "container",
          "block_id": "container1",
          "title": {
            "type": "plain_text",
            "text": "Container Title"
          },
          "subtitle": {
            "type": "mrkdwn",
            "text": "*Bold* subtitle"
          },
          "width": "wide",
          "is_collapsible": true,
          "default_collapsed": false,
          "icon": {
            "type": "image",
            "image_url": "https://example.com/icon.png",
            "alt_text": "icon"
          },
          "child_blocks": [
            {
              "type": "section",
              "text": {
                "type": "mrkdwn",
                "text": "Section inside container."
              }
            },
            {
              "type": "divider"
            }
          ]
        }
        """#,
        #"""
        {
          "type": "container",
          "rich_text_title": {
            "type": "rich_text",
            "elements": [
              {
                "type": "rich_text_section",
                "elements": [
                  {
                    "type": "text",
                    "text": "Rich Title"
                  }
                ]
              }
            ]
          },
          "child_blocks": [
            {
              "type": "divider"
            }
          ]
        }
        """#,
        #"""
        {
          "type": "container",
          "title": {
            "type": "plain_text",
            "text": "With divider"
          },
          "has_header_divider": true,
          "child_blocks": [
            {
              "type": "divider"
            }
          ]
        }
        """#,
        #"""
        {
          "type": "task_card",
          "task_id": "task_1",
          "title": "Fetching weather data",
          "status": "in_progress",
          "output": {
            "type": "rich_text",
            "elements": [
              {
                "type": "rich_text_section",
                "elements": [
                  {
                    "type": "text",
                    "text": "Found weather data for Chicago from 2 sources"
                  }
                ]
              }
            ]
          },
          "sources": [
            {
              "type": "url",
              "url": "https://weather.com/",
              "text": "weather.com"
            },
            {
              "type": "url",
              "url": "https://www.accuweather.com/",
              "text": "accuweather.com"
            }
          ]
        }
        """#,
    ]
}
