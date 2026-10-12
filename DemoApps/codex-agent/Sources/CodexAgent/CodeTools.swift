import Codex
import Foundation
import SlackKit

extension AgentToolset {
    static let codeSpecs: [DynamicToolSpec] = [
        function(startCodeChannel, description: """
        Start a Slack Code channel for substantial work that needs editing, running commands or showing artifacts.
        Reuses an existing channel for this conversation. The original task automatically continues there;
        tell the person where it went and do not execute it again here. Already in a code channel, reuse it.
        """, properties: ["name": ["type": "string", "minLength": 1]], required: ["name"]),
        function(publishCodeView, description: """
        Publish a view in the current code channel. HTML content is a self-contained document; diff is unified
        diff; block_kit content is a JSON array of Block Kit blocks. Canvas uses an existing canvas_id;
        pull_request uses a URL. html, block_kit and canvas require a stable key. Only use HTTPS resource domains.
        """, properties: [
            "type": ["type": "string", "enum": ["html", "diff", "block_kit", "canvas", "pull_request"]],
            "key": ["type": "string"], "content": ["type": "string"], "name": ["type": "string"],
            "url": ["type": "string", "pattern": "^https://"], "canvas_id": ["type": "string"],
            "access_level": ["type": "string", "enum": ["read", "write", "comment"]],
            "resource_domains": ["type": "array", "items": ["type": "string"]],
        ], required: ["type"]),
        function(archiveCodeChannel, description: """
        Post a final summary, attach it to this code channel, and archive the channel. Only call when the person
        asks to end or archive this task; completing a turn alone does not archive it.
        """, properties: ["summary": ["type": "string", "minLength": 1]], required: ["summary"]),
    ]

    struct StartCodeChannelArguments: Decodable { let name: String }
    struct ArchiveArguments: Decodable { let summary: String }

    struct CodeViewArguments: Decodable {
        let type: String
        let key: String?
        let content: String?
        let name: String?
        let url: String?
        let canvasId: String?
        let accessLevel: String?
        let resourceDomains: [String]?

        enum CodingKeys: String, CodingKey {
            case type, key, content, name, url
            case canvasId = "canvas_id"
            case accessLevel = "access_level"
            case resourceDomains = "resource_domains"
        }

        private func canvasAccess() throws -> CodeChannel.View.AccessLevel {
            guard let accessLevel else { return .comment }
            guard let access = CodeChannel.View.AccessLevel(rawValue: accessLevel) else {
                throw AgentToolError(description: "Unknown canvas access_level.")
            }
            return access
        }

        func view() throws -> CodeChannel.View {
            func required(_ value: String?, field: String) throws -> String {
                guard let value, !value.isEmpty else { throw AgentToolError(description: "Pass \(field).") }
                return value
            }
            switch type {
            case "html":
                return try .html(
                    key: required(key, field: "key"),
                    content: required(content, field: "content"),
                    name: name,
                    csp: resourceDomains.map { .init(resourceDomains: $0) },
                )
            case "diff": return try .diff(content: required(content, field: "content"), name: name)
            case "block_kit":
                let blocks = try JSONDecoder().decode([Block].self, from: Data(required(content, field: "content").utf8))
                return try .blockKit(key: required(key, field: "key"), blocks: blocks, name: name)
            case "canvas":
                return try .canvas(
                    key: required(key, field: "key"),
                    canvasId: required(canvasId, field: "canvas_id"),
                    accessLevel: canvasAccess(),
                    name: name,
                )
            case "pull_request": return try .pullRequest(url: required(url, field: "url"), name: name)
            default: throw AgentToolError(description: "Unknown code view type.")
            }
        }
    }
}
