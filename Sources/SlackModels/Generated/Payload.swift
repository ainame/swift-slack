@_spi(Generated) import OpenAPIRuntime
#if os(Linux)
@preconcurrency import struct Foundation.Data
@preconcurrency import struct Foundation.Date
@preconcurrency import struct Foundation.URL
#else
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.URL
#endif

/// - Remark: Generated from `#/components/schemas/Payload`.
public struct Payload: Codable, Hashable, Sendable {
    /// - Remark: Generated from `#/components/schemas/Payload/action`.
    public var action: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/actor`.
    public var actor: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/app_id`.
    public var appId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/billing_reason`.
    public var billingReason: [Swift.String]?
    /// - Remark: Generated from `#/components/schemas/Payload/bot_user_id`.
    public var botUserId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/bundle_size_kb`.
    public var bundleSizeKb: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/channel_id`.
    public var channelId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/code`.
    public var code: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/current_step`.
    public var currentStep: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/datastore_name`.
    public var datastoreName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/details`.
    public var details: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/elapsed_ms`.
    public var elapsedMs: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/error`.
    public var error: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/error_stage`.
    public var errorStage: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/exec_outcome`.
    public var execOutcome: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/extra_message`.
    public var extraMessage: Message?
    /// - Remark: Generated from `#/components/schemas/Payload/function_execution_id`.
    public var functionExecutionId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/function_id`.
    public var functionId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/function_name`.
    public var functionName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/function_type`.
    public var functionType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/http_status_code`.
    public var httpStatusCode: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/inputs`.
    public var inputs: Inputs?
    /// - Remark: Generated from `#/components/schemas/Payload/is_billing_excluded`.
    public var isBillingExcluded: Swift.Bool?
    /// - Remark: Generated from `#/components/schemas/Payload/log`.
    public var log: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/message`.
    public var message: Message?
    /// - Remark: Generated from `#/components/schemas/Payload/outputs`.
    public var outputs: Outputs?
    /// - Remark: Generated from `#/components/schemas/Payload/provider_key`.
    public var providerKey: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/request_type`.
    public var requestType: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/server_name`.
    public var serverName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/team_id`.
    public var teamId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/tokens_checked`.
    public var tokensChecked: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/tool_count`.
    public var toolCount: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/tool_name`.
    public var toolName: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/total_steps`.
    public var totalSteps: Swift.Int?
    /// - Remark: Generated from `#/components/schemas/Payload/trigger`.
    public var trigger: Trigger?
    /// - Remark: Generated from `#/components/schemas/Payload/type`.
    public var _type: Swift.String
    /// - Remark: Generated from `#/components/schemas/Payload/user_id`.
    public var userId: Swift.String?
    /// - Remark: Generated from `#/components/schemas/Payload/workflow_name`.
    public var workflowName: Swift.String?
    /// Creates a new `Payload`.
    ///
    /// - Parameters:
    ///   - action:
    ///   - actor:
    ///   - appId:
    ///   - billingReason:
    ///   - botUserId:
    ///   - bundleSizeKb:
    ///   - channelId:
    ///   - code:
    ///   - currentStep:
    ///   - datastoreName:
    ///   - details:
    ///   - elapsedMs:
    ///   - error:
    ///   - errorStage:
    ///   - execOutcome:
    ///   - extraMessage:
    ///   - functionExecutionId:
    ///   - functionId:
    ///   - functionName:
    ///   - functionType:
    ///   - httpStatusCode:
    ///   - inputs:
    ///   - isBillingExcluded:
    ///   - log:
    ///   - message:
    ///   - outputs:
    ///   - providerKey:
    ///   - requestType:
    ///   - serverName:
    ///   - teamId:
    ///   - tokensChecked:
    ///   - toolCount:
    ///   - toolName:
    ///   - totalSteps:
    ///   - trigger:
    ///   - _type:
    ///   - userId:
    ///   - workflowName:
    public init(
        action: Swift.String? = nil,
        actor: Swift.String? = nil,
        appId: Swift.String? = nil,
        billingReason: [Swift.String]? = nil,
        botUserId: Swift.String? = nil,
        bundleSizeKb: Swift.Int? = nil,
        channelId: Swift.String? = nil,
        code: Swift.String? = nil,
        currentStep: Swift.Int? = nil,
        datastoreName: Swift.String? = nil,
        details: Swift.String? = nil,
        elapsedMs: Swift.Int? = nil,
        error: Swift.String? = nil,
        errorStage: Swift.String? = nil,
        execOutcome: Swift.String? = nil,
        extraMessage: Message? = nil,
        functionExecutionId: Swift.String? = nil,
        functionId: Swift.String? = nil,
        functionName: Swift.String? = nil,
        functionType: Swift.String? = nil,
        httpStatusCode: Swift.Int? = nil,
        inputs: Inputs? = nil,
        isBillingExcluded: Swift.Bool? = nil,
        log: Swift.String? = nil,
        message: Message? = nil,
        outputs: Outputs? = nil,
        providerKey: Swift.String? = nil,
        requestType: Swift.String? = nil,
        serverName: Swift.String? = nil,
        teamId: Swift.String? = nil,
        tokensChecked: Swift.Int? = nil,
        toolCount: Swift.Int? = nil,
        toolName: Swift.String? = nil,
        totalSteps: Swift.Int? = nil,
        trigger: Trigger? = nil,
        _type: Swift.String,
        userId: Swift.String? = nil,
        workflowName: Swift.String? = nil,
    ) {
        self.action = action
        self.actor = actor
        self.appId = appId
        self.billingReason = billingReason
        self.botUserId = botUserId
        self.bundleSizeKb = bundleSizeKb
        self.channelId = channelId
        self.code = code
        self.currentStep = currentStep
        self.datastoreName = datastoreName
        self.details = details
        self.elapsedMs = elapsedMs
        self.error = error
        self.errorStage = errorStage
        self.execOutcome = execOutcome
        self.extraMessage = extraMessage
        self.functionExecutionId = functionExecutionId
        self.functionId = functionId
        self.functionName = functionName
        self.functionType = functionType
        self.httpStatusCode = httpStatusCode
        self.inputs = inputs
        self.isBillingExcluded = isBillingExcluded
        self.log = log
        self.message = message
        self.outputs = outputs
        self.providerKey = providerKey
        self.requestType = requestType
        self.serverName = serverName
        self.teamId = teamId
        self.tokensChecked = tokensChecked
        self.toolCount = toolCount
        self.toolName = toolName
        self.totalSteps = totalSteps
        self.trigger = trigger
        self._type = _type
        self.userId = userId
        self.workflowName = workflowName
    }

    public enum CodingKeys: String, CodingKey {
        case action
        case actor
        case appId = "app_id"
        case billingReason = "billing_reason"
        case botUserId = "bot_user_id"
        case bundleSizeKb = "bundle_size_kb"
        case channelId = "channel_id"
        case code
        case currentStep = "current_step"
        case datastoreName = "datastore_name"
        case details
        case elapsedMs = "elapsed_ms"
        case error
        case errorStage = "error_stage"
        case execOutcome = "exec_outcome"
        case extraMessage = "extra_message"
        case functionExecutionId = "function_execution_id"
        case functionId = "function_id"
        case functionName = "function_name"
        case functionType = "function_type"
        case httpStatusCode = "http_status_code"
        case inputs
        case isBillingExcluded = "is_billing_excluded"
        case log
        case message
        case outputs
        case providerKey = "provider_key"
        case requestType = "request_type"
        case serverName = "server_name"
        case teamId = "team_id"
        case tokensChecked = "tokens_checked"
        case toolCount = "tool_count"
        case toolName = "tool_name"
        case totalSteps = "total_steps"
        case trigger
        case _type = "type"
        case userId = "user_id"
        case workflowName = "workflow_name"
    }
}
