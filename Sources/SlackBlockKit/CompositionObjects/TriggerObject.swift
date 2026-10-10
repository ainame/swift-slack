import Foundation

public struct TriggerObject: Codable, Hashable, Sendable {
    public let url: URL
    public let customizableInputParameters: [InputParameter]?

    public init(url: URL, customizableInputParameters: [InputParameter]? = nil) {
        self.url = url
        self.customizableInputParameters = customizableInputParameters
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case customizableInputParameters = "customizable_input_parameters"
    }
}

public struct InputParameter: Codable, Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
