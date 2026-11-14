import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import SlackBlockKit
@testable import SlackClient
import Testing

struct FormEncodingMiddlewareTests {
    @Test
    func `preserves typed block kit payloads in form encoding`() async throws {
        let blockValue = #"{"command":"git diff --stat main..HEAD && printf '\n---\n' && echo a&b=c","approved":true}"#
        let payload = Operations.ChatPostMessage.Input.Body.JsonPayload(
            blocks: [
                .section(SectionBlock(
                    text: .init(type: .mrkdwn, text: "*Approval required*\nReview diff", verbatim: true),
                )),
                .actions(ActionsBlock(
                    elements: [
                        .button(ButtonElement(
                            text: .init(type: .plainText, text: "Approve"),
                            actionId: "approval_approve",
                            value: blockValue,
                        )),
                    ],
                    blockId: "approval_actions",
                )),
            ],
            channel: "C123",
            replyBroadcast: true,
            text: "Approval required",
        )

        let jsonData = try JSONEncoder().encode(payload)
        var request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "slack.com",
            path: "/api/chat.postMessage",
        )
        request.headerFields[HTTPField.Name.contentType] = "application/json; charset=utf-8"

        let middleware = FormEncodingMiddleware()
        let intercepted = try await middleware.intercept(
            request,
            body: HTTPBody(jsonData),
            baseURL: #require(URL(string: "https://slack.com/api")),
            operationID: "chatPostMessage",
            next: { request, body, _ in
                (HTTPResponse(status: .ok, headerFields: request.headerFields), body)
            },
        )

        #expect(intercepted.0.headerFields[HTTPField.Name.contentType] == "application/x-www-form-urlencoded")
        let body = try #require(intercepted.1)
        let formString = try await String(decoding: Data(collecting: body, upTo: .max), as: UTF8.self)
        let fields = try #require(parseFormBody(formString))

        #expect(fields["channel"] == "C123")
        #expect(fields["text"] == "Approval required")
        #expect(fields["reply_broadcast"] == "true")

        let blocksValue = try #require(fields["blocks"])
        let blocksData = try #require(blocksValue.data(using: String.Encoding.utf8))
        let blocks = try JSONDecoder().decode([Block].self, from: blocksData)

        guard case let .actions(actionsBlock)? = blocks.last,
              case let .button(buttonElement)? = actionsBlock.elements.first else {
            Issue.record("Expected final block to be an actions block with a button")
            return
        }

        #expect(buttonElement.value == blockValue)
    }

    @Test
    func `preserves a numeric Slackbot skills limit of one`() async throws {
        let payload = Operations.SlackbotSkillsList.Input.Body.JsonPayload(limit: 1)
        var request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "slack.com",
            path: "/api/slackbot.skills.list",
        )
        request.headerFields[.contentType] = "application/json"
        let (_, body) = try await FormEncodingMiddleware().intercept(
            request,
            body: HTTPBody(JSONEncoder().encode(payload)),
            baseURL: #require(URL(string: "https://slack.com/api")),
            operationID: "slackbotSkillsList",
            next: { _, body, _ in (HTTPResponse(status: .ok), body) },
        )
        let data = try await Data(collecting: #require(body), upTo: .max)
        #expect(String(decoding: data, as: UTF8.self) == "limit=1")
    }

    @Test
    func `encodes admin Slackbot skill ID lists as comma-separated form values`() async throws {
        let payload = Operations.AdminSlackbotSkillsPublish.Input.Body.JsonPayload(skillIds: ["SK1", "SK2"])
        var request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "slack.com",
            path: "/api/admin.slackbot.skills.publish",
        )
        request.headerFields[.contentType] = "application/json"
        let (_, body) = try await FormEncodingMiddleware().intercept(
            request,
            body: HTTPBody(JSONEncoder().encode(payload)),
            baseURL: #require(URL(string: "https://slack.com/api")),
            operationID: Operations.AdminSlackbotSkillsPublish.id,
            next: { _, body, _ in (HTTPResponse(status: .ok), body) },
        )
        let data = try await Data(collecting: #require(body), upTo: .max)
        let fields = try #require(parseFormBody(String(decoding: data, as: UTF8.self)))
        #expect(fields == ["skill_ids": "SK1,SK2"])
    }

    private func parseFormBody(_ body: String) -> [String: String]? {
        var fields: [String: String] = [:]

        for pair in body.split(separator: "&") {
            guard let separatorIndex = pair.firstIndex(of: "=") else {
                return nil
            }
            let key = String(pair[..<separatorIndex]).removingPercentEncoding
            let value = String(pair[pair.index(after: separatorIndex)...]).removingPercentEncoding
            guard let key, let value else {
                return nil
            }
            fields[key] = value
        }

        return fields
    }
}
