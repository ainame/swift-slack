import Foundation
import SlackClient
import Testing

struct ListRecordLinkTests {
    @Test(arguments: [
        #"{"originalUrl":"https://example.com","displayAsUrl":false,"displayName":"Example"}"#,
        #"{"original_url":"https://example.com","display_as_url":false,"display_name":"Example"}"#,
    ])
    func `list record links decode both spellings and encode snake case`(link: String) throws {
        let recordJSON = #"{"fields":[{"link":["# + link + "]}]}"
        let decoder = JSONDecoder()
        let record = try decoder.decode(ListRecord.self, from: Data(recordJSON.utf8))
        let value = try #require(record.fields?.first?.link?.first)
        #expect(value.originalUrl == "https://example.com")
        #expect(value.displayAsUrl == false)
        #expect(value.displayName == "Example")

        let attachmentJSON = #"{"list_record":{"record":"# + recordJSON + "}}"
        let attachment = try decoder.decode(Attachment.self, from: Data(attachmentJSON.utf8))
        let embedded = try #require(attachment.listRecord?.record?.fields?.first?.link?.first)
        #expect(embedded.originalUrl == value.originalUrl)
        #expect(embedded.displayAsUrl == value.displayAsUrl)
        #expect(embedded.displayName == value.displayName)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary
        #expect(encoded == ["original_url": "https://example.com", "display_as_url": false, "display_name": "Example"] as NSDictionary)
    }
}
