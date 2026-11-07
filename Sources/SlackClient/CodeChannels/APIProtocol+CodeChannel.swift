#if WebAPI_Agents
import Foundation
import OpenAPIRuntime

extension APIProtocol {
    /// Updates a code channel's properties with `agents.conversations.setProperties`.
    ///
    /// Slack updates only the properties you send and answers `no_properties_provided` when you send none.
    /// To set the session's title or status, use `agentsSessionsRename` and `agentsSessionsSetStatus`.
    ///
    /// - Parameters:
    ///   - channelId: The code channel to update.
    ///   - properties: The channel's context bar and summary message.
    ///   - agentResource: What the agent works on, such as a repository or a pull request.
    /// - Returns: Slack's response, whose `warning` reports adjusted input, such as a context bar cut to 5 items.
    /// - Throws: ``CodeChannel/Error`` when Slack answers `"ok": false`.
    @discardableResult
    public func setCodeChannelProperties(
        channelId: String,
        properties: CodeChannel.Properties? = nil,
        agentResource: CodeChannel.AgentResource? = nil,
    ) async throws -> Components.Schemas.AgentsConversationsSetPropertiesResponse {
        let response = try await agentsConversationsSetProperties(body: .json(.init(
            channelId: channelId,
            codeChannel: properties.map { try CodeChannel.container($0) },
            agentResource: agentResource.map { try CodeChannel.container($0) },
        ))).ok.body.json
        try CodeChannel.check("agents.conversations.setProperties", ok: response.ok, error: response.error)
        return response
    }

    /// Replaces the commands the app registers in a code channel with `agents.conversations.setCommands`.
    ///
    /// Pass an empty array to clear the app's commands. A channel holds at most 10 commands across all agents.
    ///
    /// - Parameters:
    ///   - channelId: The code channel to register the commands in.
    ///   - commands: The app's complete set of commands.
    /// - Returns: Slack's response.
    /// - Throws: ``CodeChannel/Error`` when Slack answers `"ok": false`.
    @discardableResult
    public func setCodeChannelCommands(
        channelId: String,
        commands: [CodeChannel.Command],
    ) async throws -> Components.Schemas.AgentsConversationsSetCommandsResponse {
        let response = try await agentsConversationsSetCommands(body: .json(.init(
            channelId: channelId,
            commands: CodeChannel.container(commands),
        ))).ok.body.json
        try CodeChannel.check("agents.conversations.setCommands", ok: response.ok, error: response.error)
        return response
    }

    /// Creates or updates a view tab in a code channel with `agents.conversations.setView`.
    ///
    /// - Parameters:
    ///   - channelId: The code channel to show the view in.
    ///   - view: The view's kind and content.
    /// - Returns: Slack's response, including the view's ID.
    /// - Throws: ``CodeChannel/Error`` when Slack answers `"ok": false`.
    @discardableResult
    public func setCodeChannelView(
        channelId: String,
        view: CodeChannel.View,
    ) async throws -> Components.Schemas.AgentsConversationsSetViewResponse {
        let response = try await agentsConversationsSetView(body: .json(view.payload(channelId: channelId)))
            .ok.body.json
        try CodeChannel.check("agents.conversations.setView", ok: response.ok, error: response.error)
        return response
    }
}

extension CodeChannel {
    /// Swift Slack decodes `"ok": false` responses without throwing, so the helpers check them themselves.
    fileprivate static func check(_ method: String, ok: Bool, error: String?) throws {
        guard ok else {
            throw Error(method: method, code: error ?? "unknown_error")
        }
    }

    /// Converts a value to the untyped container a generated request body takes.
    ///
    /// slack-api-ref declares these arguments as objects and arrays without schemas, so the generated bodies
    /// take `OpenAPIObjectContainer` and `OpenAPIArrayContainer`.
    fileprivate static func container<Container: Decodable>(_ value: some Encodable) throws -> Container {
        try JSONDecoder().decode(Container.self, from: JSONEncoder().encode(value))
    }
}

extension CodeChannel.View {
    fileprivate func payload(
        channelId: String,
    ) throws -> Operations.AgentsConversationsSetView.Input.Body.JsonPayload {
        switch self {
        case let .html(key, content, name, csp):
            try .init(
                channelId: channelId,
                _type: "html",
                viewKey: key,
                content: content,
                name: name,
                csp: csp.map { try CodeChannel.container($0) },
            )
        case let .diff(content, baseBranch, headBranch, name):
            .init(
                channelId: channelId,
                _type: "diff",
                content: content,
                baseBranch: baseBranch,
                headBranch: headBranch,
                name: name,
            )
        case let .blockKit(key, blocks, name):
            .init(channelId: channelId, _type: "block_kit", viewKey: key, blocks: blocks, name: name)
        case let .canvas(key, canvasId, accessLevel, agentContentHash, name):
            .init(
                channelId: channelId,
                _type: "canvas",
                viewKey: key,
                canvasId: canvasId,
                accessLevel: accessLevel?.rawValue,
                agentContentHash: agentContentHash,
                name: name,
            )
        case let .pullRequest(url, name):
            .init(channelId: channelId, _type: "pull_request", prUrl: url, name: name)
        }
    }
}
#endif
