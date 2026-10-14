import Codex
import Foundation

/// The tools registered with Codex. `show_cards` carries ``SlackUI`` cards; the others act through
/// ``SlackAgentTools``.
///
/// swift-codex runs a handler while it reads the app-server's messages, so a handler that waits, as
/// `ask_user` does for a click, holds every other message until it returns. Stopping a turn resolves the
/// question first so the interrupt can go through.
enum AgentToolset {
    static let setTitle = "set_title"
    static let readSlack = "read_slack"
    static let askUser = "ask_user"
    static let startCodeChannel = "start_code_channel"
    static let publishCodeView = "publish_code_view"
    static let archiveCodeChannel = "archive_code_channel"
    static let uploadFile = "upload_file"

    static let specs: [DynamicToolSpec] = [
        function(
            SlackUI.toolName,
            description: """
            Show cards under your answer in Slack, one per item worth highlighting. Each card may link to an \
            https URL and offer a follow-up question the person can ask with one click.
            """,
            properties: [
                "cards": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 10,
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "maxLength": 150],
                            "subtitle": ["type": "string", "maxLength": 150],
                            "body": ["type": "string", "maxLength": 200, "description": "Slack mrkdwn"],
                            "url": ["type": "string", "pattern": "^https://"],
                            "ask": ["type": "string", "maxLength": 2000, "description": "A follow-up question"],
                        ],
                        "additionalProperties": false,
                    ],
                ],
            ],
            required: ["cards"],
        ),
        function(
            setTitle,
            description: "Rename this Slack conversation to a short title that says what it is about, once the topic is clear.",
            properties: ["title": ["type": "string", "minLength": 1, "maxLength": 200]],
            required: ["title"],
        ),
        function(
            readSlack,
            description: """
            Read recent messages from this Slack conversation: the current thread, or the channel it is in. \
            Use it when the person refers to something said earlier.
            """,
            properties: [
                "scope": ["type": "string", "enum": ["thread", "channel"]],
                "limit": ["type": "integer", "minimum": 1, "maximum": 50],
            ],
            required: ["scope"],
        ),
        function(
            askUser,
            description: """
            Ask the person to choose between a few options and wait for their answer. Use it before acting on \
            a choice that is theirs to make, such as which approach to take.
            """,
            properties: [
                "question": ["type": "string", "minLength": 1, "maxLength": 500],
                "options": [
                    "type": "array",
                    "minItems": 2,
                    "maxItems": 5,
                    "items": ["type": "string", "minLength": 1, "maxLength": 75],
                ],
            ],
            required: ["question", "options"],
        ),
    ] + codeSpecs

    static func title(for tool: String) -> String {
        switch tool {
        case SlackUI.toolName: "Prepare cards"
        case setTitle: "Rename the conversation"
        case readSlack: "Read the conversation"
        case askUser: "Ask you a question"
        default: "Use \(tool)"
        }
    }

    /// Answers a tool call. `show_cards` only checks its arguments: the cards are read from the completed
    /// tool call item.
    static func handle(_ call: DynamicToolCallParams, tools: SlackAgentTools, workspace: String? = nil) async -> DynamicToolCallResponse {
        guard call.namespace == nil else {
            return reply("There is no tool named \(call.tool).", success: false)
        }
        do {
            let arguments = try JSONEncoder().encode(call.arguments)
            switch call.tool {
            case uploadFile:
                guard tools.currentCodeChannel != nil, let workspace else {
                    throw AgentToolError(description: "Uploads require a writable Code channel worktree.")
                }
                let args = try decode(UploadArguments.self, from: arguments)
                let file = try WorkspaceUpload.read(path: args.path, workspace: workspace)
                let result = try await tools.uploadFile(file, title: args.title)
                return try reply(String(decoding: JSONEncoder().encode(result), as: UTF8.self), success: true)
            case startCodeChannel:
                let args = try decode(StartCodeChannelArguments.self, from: arguments)
                guard !args.name.isEmpty else { throw AgentToolError(description: "Pass a channel name.") }
                let channel = try await tools.startCodeChannel(name: args.name)
                if tools.currentCodeChannel == channel {
                    return reply("You are already in <#\(channel)>. Continue the requested work here now. No task was handed off and no new channel was created.", success: true)
                }
                return reply("The task continues in <#\(channel)>. Do not perform this task again in the origin thread.", success: true)
            case publishCodeView:
                let args = try decode(CodeViewArguments.self, from: arguments)
                try await tools.publishView(args.view())
                return reply("Published the code channel view.", success: true)
            case archiveCodeChannel:
                let args = try decode(ArchiveArguments.self, from: arguments)
                guard !args.summary.isEmpty else { throw AgentToolError(description: "Pass a summary.") }
                try await tools.archiveCodeChannel(summary: args.summary)
                return reply("Posted the summary and archived the code channel.", success: true)
            case SlackUI.toolName:
                _ = try SlackUI(arguments: arguments)
                return reply("The cards will appear under your answer.", success: true)
            case setTitle:
                let title = try decode(SetTitleArguments.self, from: arguments).title
                guard !title.isEmpty else {
                    return reply("Pass a non-empty title.", success: false)
                }
                try await tools.setTitle(title)
                return reply("Renamed the conversation.", success: true)
            case readSlack:
                let read = try decode(ReadSlackArguments.self, from: arguments)
                let limit = min(max(read.limit ?? 20, 1), 50)
                return try await reply(tools.readSlack(read.scope, limit: limit), success: true)
            case askUser:
                let ask = try decode(AskUserArguments.self, from: arguments)
                guard !ask.question.isEmpty, (2 ... 5).contains(ask.options.count) else {
                    return reply("Pass a question and two to five options.", success: false)
                }
                let choice = try await tools.askUser(ask.question, options: ask.options)
                return reply("The person chose: \(choice)", success: true)
            default:
                return reply("There is no tool named \(call.tool).", success: false)
            }
        } catch let error as SlackUI.InvalidArguments {
            return reply(error.message, success: false)
        } catch let error as AgentToolError {
            return reply(error.description, success: false)
        } catch {
            return reply("The tool failed: \(error)", success: false)
        }
    }

    private struct SetTitleArguments: Decodable {
        var title: String
    }

    private struct UploadArguments: Decodable {
        let path: String
        let title: String?
    }

    private struct ReadSlackArguments: Decodable {
        var scope: SlackReadScope
        var limit: Int?
    }

    private struct AskUserArguments: Decodable {
        var question: String
        var options: [String]
    }

    private static func decode<T: Decodable>(_: T.Type, from arguments: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: arguments)
        } catch {
            throw AgentToolError(description: "The arguments do not match the tool's schema.")
        }
    }

    /// The cards from a successful `show_cards` call.
    static func cards(from call: DynamicToolCallThreadItem) -> SlackUI? {
        guard call.tool == SlackUI.toolName, call.success == true,
              let arguments = try? JSONEncoder().encode(call.arguments) else {
            return nil
        }
        return try? SlackUI(arguments: arguments)
    }

    static func reply(_ text: String, success: Bool) -> DynamicToolCallResponse {
        DynamicToolCallResponse(contentItems: [.inputText(.init(text: text, type: .inputText))], success: success)
    }

    static func function(
        _ name: String,
        description: String,
        properties: JSONObject,
        required: [String],
    ) -> DynamicToolSpec {
        .function(.init(
            description: description,
            inputSchema: [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
                "additionalProperties": false,
            ],
            name: name,
            type: .function,
        ))
    }
}
