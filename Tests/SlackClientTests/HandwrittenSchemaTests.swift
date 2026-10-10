import Foundation
import SlackClient
import Testing

/// Shapes from scripts/handwritten_schemas.yml, which upstream java-slack-sdk reads with Gson adapters.
struct HandwrittenSchemaTests {
    @Test func `attachment video html is a string or an object`() throws {
        let html = try decode(AttachmentVideoHtml.self, #""<iframe></iframe>""#)
        #expect(html.html == "<iframe></iframe>")
        #expect(html.video == nil)

        let video = try decode(AttachmentVideoHtml.self, #"{ "source": "youtube" }"#)
        #expect(video.html == nil)
        #expect(video.video?.source == "youtube")
    }

    @Test func `workflow step input values decode every shape`() throws {
        #expect(try decode(AppWorkflowStepInputValue.self, #""hello""#).stringValue == "hello")
        #expect(try decode(AppWorkflowStepInputValue.self, "42").numberValue == 42)
        #expect(try decode(AppWorkflowStepInputValue.self, "true").boolValue == true)
        #expect(try decode(AppWorkflowStepInputValue.self, #"["U1", "U2"]"#).stringValues == ["U1", "U2"])
        #expect(try decode(AppWorkflowStepInputValue.self, #"[{ "type": "divider" }]"#).interactiveBlocks?.count == 1)

        let form = try #require(try decode(AppWorkflowStepInputValue.self, """
        { "required": ["name"], "elements": [{ "name": "name", "long": true, "default": ["a", "b"] }] }
        """).form)
        #expect(form.required == ["name"])
        #expect(form.elements?.first?.long == true)
        #expect(form.elements?.first?._default?.stringValues == ["a", "b"])
    }

    @Test func `list view grouping order is an array or an empty string`() throws {
        let grouping = try decode(ListViewGrouping.self, #"{ "group_by": "status", "order": [{ "select": ["a"] }] }"#)
        #expect(grouping.groupBy == "status")
        #expect(grouping.order?.values?.first?.select == ["a"])

        #expect(try decode(ListViewGrouping.self, #"{ "order": "" }"#).order?.values == nil)
    }

    @Test func `list cell values keep their JSON type`() throws {
        #expect(try decode(ListRecordFieldValue.self, "true").boolValue == true)
        #expect(try decode(ListRecordFieldValue.self, #""text""#).stringValue == "text")
        #expect(try decode(ListRecordFieldValue.self, "1.5").numberValue == 1.5)
    }

    #if WebAPI_Admin
    @Test func `workflow collaborator errors include the workflow`() throws {
        let json = #"{ "ok": false, "errors": [{ "user": "U1", "workflow": "Wf1", "message": "denied" }] }"#
        let added = try decode(Components.Schemas.AdminWorkflowsCollaboratorsAddResponse.self, json)
        #expect(added.errors?.first?.workflow == "Wf1")
        let removed = try decode(Components.Schemas.AdminWorkflowsCollaboratorsRemoveResponse.self, json)
        #expect(removed.errors?.first?.workflow == "Wf1")
    }
    #endif

    private func decode<T: Decodable>(_: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
