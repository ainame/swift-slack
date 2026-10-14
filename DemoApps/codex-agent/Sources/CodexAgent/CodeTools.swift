import Codex
import Foundation
import SlackKit

extension AgentToolset {
    static func specs(for session: SessionKey) -> [DynamicToolSpec] {
        guard case .codeChannel = session else {
            return specs.filter { spec in
                guard case let .function(function) = spec else { return true }
                return function.name != uploadFile
            }
        }
        return specs.filter { spec in
            guard case let .function(function) = spec else { return true }
            return function.name != startCodeChannel
        }
    }

    static func sessionInstructions(for session: SessionKey, writable: Bool, writableCodeSessions: Bool) -> String {
        let context = switch session {
        case .thread:
            """
            You are in an ordinary Slack conversation. Before editing, implementing, running tests or doing
            substantial coding work, call start_code_channel. The original task starts there automatically;
            tell the person where it went and end your origin-thread turn without doing the task twice.
            Answer questions and explanations here without creating a channel.
            """
        case let .codeChannel(channel):
            """
            You are already working in Slack Code channel <#\(channel)>. The task has already been handed off
            to THIS channel. Execute the user's actual task here now; do not create or request another channel,
            and do not end with a promise to start work elsewhere. publish_code_view shows useful artifacts;
            diff views update automatically. Only archive_code_channel when the person asks to end the task.
            """
        }
        let permissions = if writable {
            "This session has an isolated writable repository checkout."
        } else if case .thread = session, writableCodeSessions {
            "This origin conversation is read-only, but start_code_channel opens an isolated writable checkout for the task."
        } else {
            "This session is read-only. You may investigate and explain, but cannot edit files. If editing is requested, explain that CODEX_SESSION_WORKSPACES must be configured; do not claim the changes were made."
        }
        return context + "\n" + permissions
    }

    static let codeSpecs: [DynamicToolSpec] = [
        makeToolSpec(uploadFile, description: """
        Upload a local file from this Code channel's writable worktree and share it in this channel.
        Pass a relative or absolute path and an optional title. Regular files only, up to 20 MiB;
        symlinks and .git/.env files cannot be uploaded. Returns file_id, permalink and slack_file.
        For an image artifact, use the returned slack_file in a Block Kit image block with alt_text,
        then call publish_code_view with type block_kit. Never use a local path as an image URL.
        """, properties: ["path": ["type": "string", "minLength": 1], "title": ["type": "string", "maxLength": 200]], required: ["path"]),
        makeToolSpec(startCodeChannel, description: """
        Start a Slack Code channel for substantial work that needs editing, running commands or showing artifacts.
        Reuses an existing channel for this conversation. The original task automatically continues there;
        tell the person where it went and do not execute it again here. Already in a code channel, reuse it.
        """, properties: ["name": ["type": "string", "minLength": 1]], required: ["name"]),
        makeToolSpec(publishCodeView, description: """
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
        makeToolSpec(archiveCodeChannel, description: """
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
