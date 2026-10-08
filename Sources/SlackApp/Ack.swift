import Foundation
import SlackBlockKit

/// Provides acknowledgment functionality for Slack app interactions.
public struct Ack: Sendable {
    private let basicHandler: @Sendable () async throws -> Void
    private let viewHandler: @Sendable (String, View?) async throws -> Void
    private let errorHandler: @Sendable ([String: String]) async throws -> Void
    private let optionsHandler: @Sendable (OptionsResponse) async throws -> Void

    init(
        basicHandler: @Sendable @escaping () async throws -> Void,
        viewHandler: @Sendable @escaping (String, View?) async throws -> Void,
        errorHandler: @Sendable @escaping ([String: String]) async throws -> Void,
        optionsHandler: @Sendable @escaping (OptionsResponse) async throws -> Void,
    ) {
        self.basicHandler = basicHandler
        self.viewHandler = viewHandler
        self.errorHandler = errorHandler
        self.optionsHandler = optionsHandler
    }

    public func callAsFunction() async throws {
        try await basicHandler()
    }

    public func callAsFunction(responseAction: ResponseAction, view: View) async throws {
        try await viewHandler(responseAction.rawValue, view)
    }

    /// Responds to a `view_submission` request with a response action that takes no view.
    ///
    /// Use `.clear` to close every view in the modal stack, like Bolt's `ack({ response_action: "clear" })`.
    public func callAsFunction(responseAction: ViewlessResponseAction) async throws {
        try await viewHandler(responseAction.rawValue, nil)
    }

    public func callAsFunction(errors: [String: String]) async throws {
        try await errorHandler(errors)
    }

    /// Responds to a `block_suggestion` request with the options to show in the external select menu.
    ///
    /// Slack shows at most 100 options.
    public func callAsFunction(options: [OptionObject]) async throws {
        try await optionsHandler(OptionsResponse(options: options, optionGroups: nil))
    }

    /// Responds to a `block_suggestion` request with option groups to show in the external select menu.
    ///
    /// Slack shows at most 100 option groups.
    public func callAsFunction(optionGroups: [OptionGroupObject]) async throws {
        try await optionsHandler(OptionsResponse(options: nil, optionGroups: optionGroups))
    }
}

/// The acknowledgement body for a `block_suggestion` request.
struct OptionsResponse: Encodable {
    let options: [OptionObject]?
    let optionGroups: [OptionGroupObject]?

    private enum CodingKeys: String, CodingKey {
        case options
        case optionGroups = "option_groups"
    }
}

extension Ack {
    public enum ResponseAction: String, Sendable {
        case update
        case push
        @available(*, deprecated, message: "Slack documents clear without a view. Use ack(responseAction: .clear), which sends it without one. ResponseAction.clear will be removed in a 2027 release.")
        case clear
    }

    /// A `view_submission` response action that is sent without a view.
    public enum ViewlessResponseAction: String, Sendable {
        /// Closes every view in the modal stack.
        case clear
    }
}
