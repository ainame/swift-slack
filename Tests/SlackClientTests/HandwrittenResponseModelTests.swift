import Foundation
@testable import SlackClient
import SlackModels
import Testing

struct HandwrittenResponseModelTests {
    @Test
    func `calls add response decodes the calls api call`() throws {
        #if WebAPI_Calls
        let json = """
        {
            "ok": true,
            "call": {
                "id": "R123",
                "date_start": 1700000000,
                "external_unique_id": "external-123",
                "join_url": "https://example.com/join",
                "desktop_app_join_url": "callapp://join/123",
                "external_display_id": "123-456",
                "title": "Weekly sync",
                "channels": ["C123"],
                "users": [
                    { "slack_id": "U123" },
                    {
                        "external_id": "guest-1",
                        "display_name": "Guest",
                        "avatar_url": "https://example.com/guest.png"
                    }
                ]
            }
        }
        """

        let response = try JSONDecoder().decode(
            Components.Schemas.CallsAddResponse.self,
            from: #require(json.data(using: .utf8)),
        )

        let call = try #require(response.call)
        #expect(call.id == "R123")
        #expect(call.dateStart == 1_700_000_000)
        #expect(call.joinUrl == "https://example.com/join")
        #expect(call.title == "Weekly sync")
        #expect(call.channels == ["C123"])
        #expect(call.users == [
            CallParticipant(slackId: "U123"),
            CallParticipant(externalId: "guest-1", displayName: "Guest", avatarUrl: "https://example.com/guest.png"),
        ])
        #endif
    }

    @Test
    func `admin workflows search decodes the java-slack-sdk fixture`() throws {
        #if WebAPI_Admin
        let response = try decodeFixture(Components.Schemas.AdminWorkflowsSearchResponse.self, "admin.workflows.search")

        let workflow = try #require(response.workflows?.first)
        #expect(workflow.id != nil)
        #expect(workflow.teamId != nil)
        #expect(workflow.title != nil)
        #expect(workflow.isPublished != nil)
        #expect(workflow.icons?.image96 != nil)
        #expect(workflow.inputParameters?.isEmpty == false)
        #expect(workflow.steps?.first?.inputs?.isEmpty == false)
        #expect(try JSONEncoder().encode(workflow) != Data("{}".utf8))
        #endif
    }

    @Test
    func `usergroups list decodes every java-slack-sdk usergroup field`() throws {
        #if WebAPI_Usergroups
        let response = try decodeFixture(Components.Schemas.UsergroupsListResponse.self, "usergroups.list")

        let usergroup = try #require(response.usergroups?.first)
        #expect(usergroup.id != nil)
        #expect(usergroup.userCount != nil)
        #expect(usergroup.deletedBy != nil)
        #expect(usergroup.prefs?.channels != nil)
        #endif
    }

    @Test
    func `admin workflows collaborators add decodes per-user errors`() throws {
        #if WebAPI_Admin
        let response = try decodeFixture(
            Components.Schemas.AdminWorkflowsCollaboratorsAddResponse.self,
            "admin.workflows.collaborators.add",
        )

        let error = try #require(response.errors?.first)
        #expect(error.user != nil)
        #expect(error.message != nil)
        #expect(error.workflow != nil)
        #endif
    }

    @Test
    func `app workflow step input values decode every shape`() throws {
        let json = """
        {
            "text": { "value": "hello" },
            "users": { "value": ["U1", "U2"] },
            "form": {
                "value": {
                    "required": ["name"],
                    "elements": [
                        { "name": "name", "type": "string", "long": true, "default": ["a", "b"] }
                    ]
                }
            },
            "blocks": { "value": [{ "type": "divider" }] }
        }
        """

        let inputs = try JSONDecoder().decode(
            [String: AppWorkflow.StepInput].self,
            from: #require(json.data(using: .utf8)),
        )

        #expect(inputs["text"]?.value == .init(stringValue: "hello"))
        #expect(inputs["users"]?.value == .init(stringValues: ["U1", "U2"]))
        let form = try #require(inputs["form"]?.value)
        #expect(form.required == ["name"])
        #expect(form.elements?.first?.isLong == true)
        #expect(form.elements?.first?.defaultValue == .init(stringValues: ["a", "b"]))
        #expect(inputs["blocks"]?.value?.interactiveBlocks?.count == 1)

        let roundTripped = try JSONDecoder().decode(
            [String: AppWorkflow.StepInput].self,
            from: JSONEncoder().encode(inputs),
        )
        #expect(roundTripped == inputs)
    }

    @Test
    func `api test response decodes echoed args`() throws {
        #if WebAPI_Api
        let json = """
        {
            "ok": false,
            "error": "my_error",
            "args": { "error": "my_error" }
        }
        """

        let response = try JSONDecoder().decode(
            Components.Schemas.APITestResponse.self,
            from: #require(json.data(using: .utf8)),
        )

        #expect(response.args == APITestArgs(error: "my_error"))
        #endif
    }

    @Test
    func `response metadata decodes next_cursor`() throws {
        #if WebAPI_Conversations
        let json = """
        {
            "ok": true,
            "channels": [],
            "response_metadata": {
                "next_cursor": "dGVhbTpDMDYxRkE1UEI=",
                "messages": ["m"],
                "warnings": ["w"]
            }
        }
        """

        let response = try JSONDecoder().decode(
            Components.Schemas.ConversationsListResponse.self,
            from: #require(json.data(using: .utf8)),
        )

        let metadata = try #require(response.responseMetadata)
        #expect(metadata.nextCursor == "dGVhbTpDMDYxRkE1UEI=")
        #expect(metadata.messages == ["m"])
        #expect(metadata.warnings?.count == 1)

        let encoded = try JSONEncoder().encode(metadata)
        #expect(try JSONDecoder().decode(ResponseMetadata.self, from: encoded) == metadata)
        #endif
    }

    /// Decodes a java-slack-sdk Web API fixture from the vendored submodule.
    private func decodeFixture<T: Decodable>(_ type: T.Type, _ method: String) throws -> T {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../vendor/java-slack-sdk/json-logs/samples/api/\(method).json")
        return try JSONDecoder().decode(type, from: Data(contentsOf: fixture))
    }
}
