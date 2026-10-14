#if WebAPI_Agents
import SlackBlockKit

/// Typed request values for the Slack Code channel methods.
///
/// Pass them to ``APIProtocol/setCodeChannelProperties(channelId:properties:agentResource:)``,
/// ``APIProtocol/setCodeChannelCommands(channelId:commands:)`` and ``APIProtocol/setCodeChannelView(channelId:view:)``.
/// The values mirror the request classes of upstream java-slack-sdk for `agents.conversations.setProperties`,
/// `agents.conversations.setCommands` and `agents.conversations.setView`.
public enum CodeChannel {
    /// The `code_channel` properties of `agents.conversations.setProperties`.
    ///
    /// Slack updates only the properties you send. ``contextBarItems`` replaces the whole context bar.
    public struct Properties: Encodable, Sendable, Hashable {
        /// The items in the channel's context bar, replacing the current ones. Slack keeps the first 5 and
        /// answers with a warning when you send more. Pass an empty array to clear the bar.
        public var contextBarItems: [ContextBarItem]?
        /// The message that summarizes the channel's work.
        public var summaryMessage: SummaryMessage?

        public init(contextBarItems: [ContextBarItem]? = nil, summaryMessage: SummaryMessage? = nil) {
            self.contextBarItems = contextBarItems
            self.summaryMessage = summaryMessage
        }

        private enum CodingKeys: String, CodingKey {
            case contextBarItems = "context_bar_items"
            case summaryMessage = "summary_message"
        }
    }

    /// One item in a code channel's context bar.
    public struct ContextBarItem: Encodable, Sendable, Hashable {
        /// The item's identity within the bar.
        public var key: String
        /// The text the item shows.
        public var label: String
        public var icon: Icon?
        /// The page the item opens.
        public var url: String?
        /// Whether the item only shows information or acts when clicked. Slack treats an `action` item with a
        /// `url` as `info` and answers with a warning.
        public var itemType: ItemType?

        public init(key: String, label: String, icon: Icon? = nil, url: String? = nil, itemType: ItemType? = nil) {
            self.key = key
            self.label = label
            self.icon = icon
            self.url = url
            self.itemType = itemType
        }

        private enum CodingKeys: String, CodingKey {
            case key
            case label
            case icon
            case url
            case itemType = "item_type"
        }

        /// The icon a context bar item shows.
        public enum Icon: String, Encodable, Sendable, Hashable {
            case branch
            case folder
            case hierarchy
            case lifeRing = "life-ring"
            case link
            case globe
            case terminal
            case code
            case search
            case lock
        }

        /// The kind of a context bar item.
        public enum ItemType: String, Encodable, Sendable, Hashable {
            /// The item shows information, opening ``ContextBarItem/url`` if set.
            case info
            /// Clicking the item sends the app a `code_channel_action` event, routed by SlackApp as
            /// `CodeChannelActionEvent`. Its arbitrary JSON fields are preserved in `additionalProperties`.
            case action
        }
    }

    /// The message that summarizes a code channel's work.
    public struct SummaryMessage: Encodable, Sendable, Hashable {
        /// The message's `ts`.
        public var messageTs: String
        /// The thread the message is in, if any.
        public var threadTs: String?

        public init(messageTs: String, threadTs: String? = nil) {
            self.messageTs = messageTs
            self.threadTs = threadTs
        }

        private enum CodingKeys: String, CodingKey {
            case messageTs = "message_ts"
            case threadTs = "thread_ts"
        }
    }

    /// The `agent_resource` properties of `agents.conversations.setProperties`, describing what the agent
    /// works on, such as a repository or a pull request.
    public struct AgentResource: Encodable, Sendable, Hashable {
        public var url: String?
        public var resourceType: String?
        public var title: String?
        public var provider: String?

        public init(url: String? = nil, resourceType: String? = nil, title: String? = nil, provider: String? = nil) {
            self.url = url
            self.resourceType = resourceType
            self.title = title
            self.provider = provider
        }

        private enum CodingKeys: String, CodingKey {
            case url
            case resourceType = "resource_type"
            case title
            case provider
        }
    }

    /// A command the agent registers in a code channel with `agents.conversations.setCommands`.
    public struct Command: Encodable, Sendable, Hashable {
        /// The command's name without the leading slash, such as `review`.
        public var name: String
        public var description: String
        /// A hint for the command's arguments, shown while typing it.
        public var argumentHint: String?
        public var shouldEscape: Bool?

        public init(name: String, description: String, argumentHint: String? = nil, shouldEscape: Bool? = nil) {
            self.name = name
            self.description = description
            self.argumentHint = argumentHint
            self.shouldEscape = shouldEscape
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case description
            case argumentHint = "argument_hint"
            case shouldEscape = "should_escape"
        }
    }

    /// The Content-Security-Policy domains of an HTML view.
    ///
    /// Slack validates the domains (HTTPS only, no private or internal hosts). It honors only
    /// ``resourceDomains`` when rendering today; it stores ``connectDomains`` without applying them.
    public struct CSP: Encodable, Sendable, Hashable {
        public var connectDomains: [String]?
        public var resourceDomains: [String]?

        public init(connectDomains: [String]? = nil, resourceDomains: [String]? = nil) {
            self.connectDomains = connectDomains
            self.resourceDomains = resourceDomains
        }

        private enum CodingKeys: String, CodingKey {
            case connectDomains = "connect_domains"
            case resourceDomains = "resource_domains"
        }
    }

    /// A view tab that `agents.conversations.setView` creates or updates.
    ///
    /// Each case takes the arguments its `type` needs. Calls with the same `key` update the same view; a diff
    /// view is one per channel. `name` labels the tab and defaults to the last path segment of `key`.
    public enum View: Sendable, Hashable {
        /// A self-contained HTML document of up to 1,000,000 bytes.
        case html(key: String, content: String, name: String? = nil, csp: CSP? = nil)
        /// A unified diff of up to 1,000,000 bytes.
        case diff(content: String, baseBranch: String? = nil, headBranch: String? = nil, name: String? = nil)
        /// Block Kit blocks.
        case blockKit(key: String, blocks: [Block], name: String? = nil)
        /// A canvas. `agentContentHash` is opaque to Slack; record the hash of what you last wrote to detect
        /// edits by people later.
        case canvas(
            key: String,
            canvasId: String,
            accessLevel: AccessLevel? = nil,
            agentContentHash: String? = nil,
            name: String? = nil,
        )
        /// A pull request.
        case pullRequest(url: String, name: String? = nil)

        /// The access a canvas view grants the channel's members. Slack defaults to `write`.
        public enum AccessLevel: String, Sendable, Hashable {
            case read
            case write
            /// Members can read and comment but not edit, so the agent remains the canvas's only author.
            case comment
        }
    }

    /// A code channel method that Slack answered with `"ok": false`.
    public struct Error: Swift.Error, Sendable, Hashable, CustomStringConvertible {
        /// The method that failed, such as `agents.conversations.setView`.
        public var method: String
        /// Slack's error code, such as `content_too_large`.
        public var code: String

        public init(method: String, code: String) {
            self.method = method
            self.code = code
        }

        public var description: String {
            "\(method) failed: \(code)"
        }
    }
}
#endif
