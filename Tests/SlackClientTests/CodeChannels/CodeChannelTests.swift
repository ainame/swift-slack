#if WebAPI_Agents
import Foundation
import HTTPTypes
import OpenAPIRuntime
import SlackBlockKit
import SlackClient
import Testing

/// Calls the code channel helpers through the generated client against a fake HTTP transport.
struct CodeChannelTests {
    @Test
    func `sends code channel properties and agent resource`() async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.setCodeChannelProperties(
            channelId: "C1",
            properties: .init(
                contextBarItems: [
                    .init(key: "branch", label: "main", icon: .branch),
                    .init(key: "help", label: "Help", icon: .lifeRing, url: "https://example.com", itemType: .info),
                ],
                summaryMessage: .init(messageTs: "1.0", threadTs: "0.5"),
            ),
            agentResource: .init(url: "https://github.com/o/r", resourceType: "repository"),
        )

        let request = try #require(await http.requests.first)
        #expect(request.operationID == "agentsConversationsSetProperties")
        #expect(request.fields["channel_id"] == "C1")
        #expect(request.fields["title"] == nil)
        #expect(request.fields["status"] == nil)
        #expect(try request.json("code_channel") == [
            "context_bar_items": [
                ["key": "branch", "label": "main", "icon": "branch"],
                [
                    "key": "help",
                    "label": "Help",
                    "icon": "life-ring",
                    "url": "https://example.com",
                    "item_type": "info",
                ],
            ],
            "summary_message": ["message_ts": "1.0", "thread_ts": "0.5"],
        ] as NSDictionary)
        #expect(try request.json("agent_resource") == [
            "url": "https://github.com/o/r",
            "resource_type": "repository",
        ] as NSDictionary)
    }

    @Test
    func `omits the properties that are not set`() async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.setCodeChannelProperties(channelId: "C1", properties: .init(contextBarItems: []))

        let request = try #require(await http.requests.first)
        #expect(try request.json("code_channel") == ["context_bar_items": [] as [Any]] as NSDictionary)
        #expect(request.fields["agent_resource"] == nil)
    }

    @Test
    func `returns the response with Slack's warning`() async throws {
        let http = SlackHTTP(response: #"{"ok":true,"channel_id":"C1","warning":"too_many_context_bar_items"}"#)
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        let response = try await client.setCodeChannelProperties(
            channelId: "C1",
            properties: .init(contextBarItems: (1 ... 6).map { CodeChannel.ContextBarItem(key: "\($0)", label: "\($0)") }),
        )

        #expect(response.ok)
        #expect(response.warning == "too_many_context_bar_items")
    }

    @Test(arguments: [
        ([], "[]"),
        (
            [
                CodeChannel.Command(name: "review", description: "Review the diff"),
                CodeChannel.Command(name: "run", description: "Run a task", argumentHint: "[task]", shouldEscape: true),
            ],
            #"[{"description":"Review the diff","name":"review"},"#
                + #"{"argument_hint":"[task]","description":"Run a task","name":"run","should_escape":true}]"#,
        ),
    ] as [([CodeChannel.Command], String)])
    func `sends the commands, an empty array included`(commands: [CodeChannel.Command], expected: String) async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.setCodeChannelCommands(channelId: "C1", commands: commands)

        let request = try #require(await http.requests.first)
        #expect(request.operationID == "agentsConversationsSetCommands")
        #expect(request.fields["channel_id"] == "C1")
        #expect(try request.sortedJSON("commands") == expected)
    }

    @Test(arguments: [
        (
            CodeChannel.View.html(
                key: "report.html",
                content: "<html></html>",
                name: "Report",
                csp: .init(connectDomains: ["https://api.example.com"], resourceDomains: ["https://cdn.example.com"]),
            ),
            [
                "type": "html",
                "view_key": "report.html",
                "content": "<html></html>",
                "name": "Report",
                "csp": #"{"connect_domains":["https://api.example.com"],"resource_domains":["https://cdn.example.com"]}"#,
            ],
        ),
        (
            .html(key: "report.html", content: "<html></html>"),
            ["type": "html", "view_key": "report.html", "content": "<html></html>"],
        ),
        (
            .diff(content: "diff --git", baseBranch: "main", headBranch: "fix", name: "Changes"),
            ["type": "diff", "content": "diff --git", "base_branch": "main", "head_branch": "fix", "name": "Changes"],
        ),
        (
            .canvas(key: "notes", canvasId: "F1", accessLevel: .comment, agentContentHash: "abc", name: "Notes"),
            [
                "type": "canvas",
                "view_key": "notes",
                "canvas_id": "F1",
                "access_level": "comment",
                "agent_content_hash": "abc",
                "name": "Notes",
            ],
        ),
        (
            .pullRequest(url: "https://github.com/o/r/pull/1", name: "PR"),
            ["type": "pull_request", "pr_url": "https://github.com/o/r/pull/1", "name": "PR"],
        ),
    ] as [(CodeChannel.View, [String: String])])
    func `sends the arguments of each view kind`(view: CodeChannel.View, expected: [String: String]) async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.setCodeChannelView(channelId: "C1", view: view)

        let request = try #require(await http.requests.first)
        #expect(request.operationID == "agentsConversationsSetView")
        var fields = request.fields
        let channelId = fields.removeValue(forKey: "channel_id")
        #expect(channelId == "C1")
        if fields["csp"] != nil {
            fields["csp"] = try request.sortedJSON("csp")
        }
        #expect(fields == expected)
    }

    @Test
    func `sends the blocks of a Block Kit view`() async throws {
        let http = SlackHTTP()
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        try await client.setCodeChannelView(
            channelId: "C1",
            view: .blockKit(key: "status", blocks: [.divider(DividerBlock())], name: "Status"),
        )

        let request = try #require(await http.requests.first)
        #expect(Set(request.fields.keys) == ["channel_id", "type", "view_key", "blocks", "name"])
        #expect(request.fields["type"] == "block_kit")
        #expect(request.fields["view_key"] == "status")
        #expect(request.fields["name"] == "Status")
        #expect(try request.json("blocks") == [["type": "divider"]] as NSArray)
    }

    @Test(arguments: [
        ("agentsConversationsSetProperties", "agents.conversations.setProperties"),
        ("agentsConversationsSetCommands", "agents.conversations.setCommands"),
        ("agentsConversationsSetView", "agents.conversations.setView"),
    ])
    func `throws CodeChannel.Error when Slack answers ok false`(operationID: String, method: String) async throws {
        let http = SlackHTTP(response: #"{"ok":false,"error":"channel_not_found"}"#)
        let client = await Slack(transport: http, configuration: .init(token: "xoxb-test")).client

        await #expect(throws: CodeChannel.Error(method: method, code: "channel_not_found")) {
            switch operationID {
            case "agentsConversationsSetProperties":
                try await client.setCodeChannelProperties(channelId: "C1")
            case "agentsConversationsSetCommands":
                try await client.setCodeChannelCommands(channelId: "C1", commands: [])
            default:
                try await client.setCodeChannelView(channelId: "C1", view: .pullRequest(url: "https://example.com"))
            }
        }
        #expect(await http.requests.map(\.operationID) == [operationID])
    }
}

/// Answers every request with one JSON body and records the form-encoded requests.
private actor SlackHTTP: ClientTransport {
    struct Request {
        var operationID: String
        var fields: [String: String]

        /// A field decoded from the JSON string the form encoding puts there.
        func json(_ name: String) throws -> NSObject {
            let json = try #require(fields[name])
            return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSObject)
        }

        /// A field's JSON with sorted keys, to compare against a literal.
        func sortedJSON(_ name: String) throws -> String {
            let data = try JSONSerialization.data(
                withJSONObject: json(name),
                options: [.sortedKeys, .withoutEscapingSlashes],
            )
            return String(decoding: data, as: UTF8.self)
        }
    }

    private(set) var requests: [Request] = []
    private let response: String

    init(response: String = #"{"ok":true,"channel_id":"C1"}"#) {
        self.response = response
    }

    func send(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var form = ""
        if let body {
            form = try await String(collecting: body, upTo: .max)
        }
        requests.append(Request(operationID: operationID, fields: Self.fields(of: form)))
        var httpResponse = HTTPResponse(status: .ok)
        httpResponse.headerFields[.contentType] = "application/json"
        return (httpResponse, HTTPBody(response))
    }

    private static func fields(of form: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in form.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
#endif
