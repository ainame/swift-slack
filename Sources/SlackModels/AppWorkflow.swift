import Foundation
import SlackBlockKit

/// A workflow returned by the admin workflow APIs, such as `admin.workflows.search`.
///
/// Mirrors `com.slack.api.model.admin.AppWorkflow` in java-slack-sdk. This is hand-written because
/// the generated `Workflow` name is shared with unrelated workflow shapes in other responses.
public struct AppWorkflow: Codable, Hashable, Sendable {
    public var id: Swift.String?
    public var teamId: Swift.String?
    public var workflowFunctionId: Swift.String?
    public var callbackId: Swift.String?
    public var title: Swift.String?
    public var description: Swift.String?
    public var inputParameters: [Swift.String: InputParameter]?
    public var outputParameters: [Swift.String: OutputParameter]?
    public var steps: [Step]?
    public var collaborators: [Swift.String]?
    public var icons: AppIcons?
    public var isPublished: Swift.Bool?
    public var lastUpdatedBy: Swift.String?
    public var unpublishedChangeCount: Swift.Int?
    public var appId: Swift.String?
    public var source: Swift.String?
    public var billingType: Swift.String?
    public var dateUpdated: Swift.Int?
    public var isBillable: Swift.Bool?
    public var lastPublishedVersionId: Swift.String?
    public var lastPublishedDate: Swift.String?
    public var triggerIds: [Swift.String]?
    public var isSalesHomeWorkflow: Swift.Bool?

    public init(
        id: Swift.String? = nil,
        teamId: Swift.String? = nil,
        workflowFunctionId: Swift.String? = nil,
        callbackId: Swift.String? = nil,
        title: Swift.String? = nil,
        description: Swift.String? = nil,
        inputParameters: [Swift.String: InputParameter]? = nil,
        outputParameters: [Swift.String: OutputParameter]? = nil,
        steps: [Step]? = nil,
        collaborators: [Swift.String]? = nil,
        icons: AppIcons? = nil,
        isPublished: Swift.Bool? = nil,
        lastUpdatedBy: Swift.String? = nil,
        unpublishedChangeCount: Swift.Int? = nil,
        appId: Swift.String? = nil,
        source: Swift.String? = nil,
        billingType: Swift.String? = nil,
        dateUpdated: Swift.Int? = nil,
        isBillable: Swift.Bool? = nil,
        lastPublishedVersionId: Swift.String? = nil,
        lastPublishedDate: Swift.String? = nil,
        triggerIds: [Swift.String]? = nil,
        isSalesHomeWorkflow: Swift.Bool? = nil,
    ) {
        self.id = id
        self.teamId = teamId
        self.workflowFunctionId = workflowFunctionId
        self.callbackId = callbackId
        self.title = title
        self.description = description
        self.inputParameters = inputParameters
        self.outputParameters = outputParameters
        self.steps = steps
        self.collaborators = collaborators
        self.icons = icons
        self.isPublished = isPublished
        self.lastUpdatedBy = lastUpdatedBy
        self.unpublishedChangeCount = unpublishedChangeCount
        self.appId = appId
        self.source = source
        self.billingType = billingType
        self.dateUpdated = dateUpdated
        self.isBillable = isBillable
        self.lastPublishedVersionId = lastPublishedVersionId
        self.lastPublishedDate = lastPublishedDate
        self.triggerIds = triggerIds
        self.isSalesHomeWorkflow = isSalesHomeWorkflow
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case teamId = "team_id"
        case workflowFunctionId = "workflow_function_id"
        case callbackId = "callback_id"
        case title
        case description
        case inputParameters = "input_parameters"
        case outputParameters = "output_parameters"
        case steps
        case collaborators
        case icons
        case isPublished = "is_published"
        case lastUpdatedBy = "last_updated_by"
        case unpublishedChangeCount = "unpublished_change_count"
        case appId = "app_id"
        case source
        case billingType = "billing_type"
        case dateUpdated = "date_updated"
        case isBillable = "is_billable"
        case lastPublishedVersionId = "last_published_version_id"
        case lastPublishedDate = "last_published_date"
        case triggerIds = "trigger_ids"
        case isSalesHomeWorkflow = "is_sales_home_workflow"
    }
}

extension AppWorkflow {
    public struct Step: Codable, Hashable, Sendable {
        public var id: Swift.String?
        public var functionId: Swift.String?
        public var inputs: [Swift.String: StepInput]?
        public var isPristine: Swift.Bool?

        public init(
            id: Swift.String? = nil,
            functionId: Swift.String? = nil,
            inputs: [Swift.String: StepInput]? = nil,
            isPristine: Swift.Bool? = nil,
        ) {
            self.id = id
            self.functionId = functionId
            self.inputs = inputs
            self.isPristine = isPristine
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case functionId = "function_id"
            case inputs
            case isPristine = "is_pristine"
        }
    }

    public struct StepInput: Codable, Hashable, Sendable {
        public var value: StepInputValue?
        public var hidden: Swift.Bool?
        public var locked: Swift.Bool?

        public init(
            value: StepInputValue? = nil,
            hidden: Swift.Bool? = nil,
            locked: Swift.Bool? = nil,
        ) {
            self.value = value
            self.hidden = hidden
            self.locked = locked
        }
    }

    /// A step input value, which Slack sends as a string, an array of strings,
    /// an array of blocks, or an object with `elements` and `required`.
    ///
    /// Decodes like `GsonAppWorkflowStepInputValueFactory` in java-slack-sdk.
    public struct StepInputValue: Codable, Hashable, Sendable {
        public var stringValue: Swift.String?
        public var stringValues: [Swift.String]?
        public var elements: [StepInputValueElement]?
        public var required: [Swift.String]?
        public var interactiveBlocks: [Block]?

        public init(
            stringValue: Swift.String? = nil,
            stringValues: [Swift.String]? = nil,
            elements: [StepInputValueElement]? = nil,
            required: [Swift.String]? = nil,
            interactiveBlocks: [Block]? = nil,
        ) {
            self.stringValue = stringValue
            self.stringValues = stringValues
            self.elements = elements
            self.required = required
            self.interactiveBlocks = interactiveBlocks
        }

        private enum CodingKeys: String, CodingKey {
            case elements
            case required
        }

        public init(from decoder: any Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                try self.init(
                    elements: container.decodeIfPresent([StepInputValueElement].self, forKey: .elements),
                    required: container.decodeIfPresent([Swift.String].self, forKey: .required),
                )
                return
            }

            let container = try decoder.singleValueContainer()
            if let value = try? container.decode([Swift.String].self) {
                self.init(stringValues: value.isEmpty ? nil : value)
            } else if let value = try? container.decode([Block].self) {
                self.init(interactiveBlocks: value.isEmpty ? nil : value)
            } else {
                try self.init(stringValue: decodeScalarAsString(container))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            if let stringValue {
                var container = encoder.singleValueContainer()
                try container.encode(stringValue)
            } else if let stringValues {
                var container = encoder.singleValueContainer()
                try container.encode(stringValues)
            } else if let interactiveBlocks {
                var container = encoder.singleValueContainer()
                try container.encode(interactiveBlocks)
            } else {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(elements, forKey: .elements)
                try container.encodeIfPresent(required, forKey: .required)
            }
        }
    }

    public struct StepInputValueElement: Codable, Hashable, Sendable {
        public var name: Swift.String?
        public var type: Swift.String?
        public var title: Swift.String?
        public var description: Swift.String?
        public var enumValues: [Swift.String]?
        public var choices: [Choice]?
        public var isLong: Swift.Bool?
        public var defaultValue: StepInputValueElementDefault?
        public var maxLength: Swift.Int?
        public var minLength: Swift.Int?
        public var items: Items?
        public var maxItems: Swift.Int?

        public init(
            name: Swift.String? = nil,
            type: Swift.String? = nil,
            title: Swift.String? = nil,
            description: Swift.String? = nil,
            enumValues: [Swift.String]? = nil,
            choices: [Choice]? = nil,
            isLong: Swift.Bool? = nil,
            defaultValue: StepInputValueElementDefault? = nil,
            maxLength: Swift.Int? = nil,
            minLength: Swift.Int? = nil,
            items: Items? = nil,
            maxItems: Swift.Int? = nil,
        ) {
            self.name = name
            self.type = type
            self.title = title
            self.description = description
            self.enumValues = enumValues
            self.choices = choices
            self.isLong = isLong
            self.defaultValue = defaultValue
            self.maxLength = maxLength
            self.minLength = minLength
            self.items = items
            self.maxItems = maxItems
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case type
            case title
            case description
            case enumValues = "enum"
            case choices
            case isLong = "long"
            case defaultValue = "default"
            case maxLength = "max_length"
            case minLength = "min_length"
            case items
            case maxItems = "max_items"
        }
    }

    /// The default of a step input element, which Slack sends as a string or an array of strings.
    ///
    /// Decodes like `GsonAppWorkflowStepInputValueDefaultFactory` in java-slack-sdk.
    public struct StepInputValueElementDefault: Codable, Hashable, Sendable {
        public var stringValue: Swift.String?
        public var stringValues: [Swift.String]?

        public init(
            stringValue: Swift.String? = nil,
            stringValues: [Swift.String]? = nil,
        ) {
            self.stringValue = stringValue
            self.stringValues = stringValues
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode([Swift.String].self) {
                self.init(stringValues: value)
            } else {
                try self.init(stringValue: decodeScalarAsString(container))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            if let stringValues {
                try container.encode(stringValues)
            } else {
                try container.encode(stringValue)
            }
        }
    }

    public struct Choice: Codable, Hashable, Sendable {
        public var title: Swift.String?
        public var value: Swift.String?
        public var description: Swift.String?

        public init(
            title: Swift.String? = nil,
            value: Swift.String? = nil,
            description: Swift.String? = nil,
        ) {
            self.title = title
            self.value = value
            self.description = description
        }
    }

    public struct Items: Codable, Hashable, Sendable {
        public var type: Swift.String?
        public var enumValues: [Swift.String]?
        public var choices: [Choice]?

        public init(
            type: Swift.String? = nil,
            enumValues: [Swift.String]? = nil,
            choices: [Choice]? = nil,
        ) {
            self.type = type
            self.enumValues = enumValues
            self.choices = choices
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case enumValues = "enum"
            case choices
        }
    }

    public struct InputParameter: Codable, Hashable, Sendable {
        public var type: Swift.String?
        public var name: Swift.String?
        public var title: Swift.String?
        public var description: Swift.String?
        public var isRequired: Swift.Bool?
        public var isHidden: Swift.Bool?

        public init(
            type: Swift.String? = nil,
            name: Swift.String? = nil,
            title: Swift.String? = nil,
            description: Swift.String? = nil,
            isRequired: Swift.Bool? = nil,
            isHidden: Swift.Bool? = nil,
        ) {
            self.type = type
            self.name = name
            self.title = title
            self.description = description
            self.isRequired = isRequired
            self.isHidden = isHidden
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case name
            case title
            case description
            case isRequired = "is_required"
            case isHidden = "is_hidden"
        }
    }

    public struct OutputParameter: Codable, Hashable, Sendable {
        public var type: Swift.String?
        public var name: Swift.String?
        public var title: Swift.String?
        public var description: Swift.String?
        public var isRequired: Swift.Bool?

        public init(
            type: Swift.String? = nil,
            name: Swift.String? = nil,
            title: Swift.String? = nil,
            description: Swift.String? = nil,
            isRequired: Swift.Bool? = nil,
        ) {
            self.type = type
            self.name = name
            self.title = title
            self.description = description
            self.isRequired = isRequired
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case name
            case title
            case description
            case isRequired = "is_required"
        }
    }
}

/// Reads a JSON scalar as a string, as Gson's `getAsString` does for step input values.
private func decodeScalarAsString(_ container: any SingleValueDecodingContainer) throws -> Swift.String? {
    if container.decodeNil() {
        nil
    } else if let value = try? container.decode(Swift.String.self) {
        value
    } else if let value = try? container.decode(Swift.Bool.self) {
        String(value)
    } else if let value = try? container.decode(Swift.Int.self) {
        String(value)
    } else {
        try String(container.decode(Swift.Double.self))
    }
}
