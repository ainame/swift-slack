import Foundation
@testable import SlackClient
import Testing

struct WorkflowPermissionsTests {
    @Test
    func `workflow permissions preserve dynamic workflow ids and access fields`() throws {
        #if WebAPI_Admin
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../vendor/java-slack-sdk/json-logs/samples/api/admin.workflows.permissions.lookup.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        let permissions = try #require(object["permissions"] as? [String: Any])
        let value = try #require(permissions["0000000000"] as? [String: Any])
        // The updated reference documents workflow IDs as dictionary keys.
        object["permissions"] = ["Wf123ABC": value, "Wf456DEF": value]
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = try JSONDecoder().decode(Components.Schemas.AdminWorkflowsPermissionsLookupResponse.self, from: data)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        let actual = try #require(encoded["permissions"] as? NSDictionary)
        let expected = try #require(object["permissions"] as? NSDictionary)
        #expect(actual == expected)
        #endif
    }
}
