import Foundation

/// A per-user failure in `admin.workflows.collaborators.add` or `admin.workflows.collaborators.remove`.
///
/// Mirrors `AdminWorkflowsCollaboratorsAddResponse.Error` in java-slack-sdk, plus `workflow`,
/// which the recorded responses of both methods include.
public struct WorkflowCollaboratorError: Codable, Hashable, Sendable {
    public var message: Swift.String?
    public var user: Swift.String?
    public var workflow: Swift.String?

    public init(
        message: Swift.String? = nil,
        user: Swift.String? = nil,
        workflow: Swift.String? = nil,
    ) {
        self.message = message
        self.user = user
        self.workflow = workflow
    }
}
