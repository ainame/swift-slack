import Foundation
@testable import SlackClient
import SlackModels
import Testing

struct ResponseMetadataTests {
    @Test
    func `conversations list decodes response metadata next cursor and warnings`() throws {
        #if WebAPI_Conversations
        let json = """
        {
            "ok": true,
            "channels": [],
            "warning": "superfluous_charset",
            "response_metadata": {
                "next_cursor": "dGVhbTpDMDYxRkE1UEI=",
                "messages": ["[WARN] A Content-Type HTTP header was presented"],
                "warnings": ["superfluous_charset"]
            }
        }
        """

        let response = try JSONDecoder().decode(
            Components.Schemas.ConversationsListResponse.self,
            from: #require(json.data(using: .utf8)),
        )

        let metadata = try #require(response.responseMetadata)
        #expect(metadata.nextCursor == "dGVhbTpDMDYxRkE1UEI=")
        #expect(metadata.messages == ["[WARN] A Content-Type HTTP header was presented"])
        #expect(metadata.warnings == ["superfluous_charset"])
        #endif
    }
}
