import CoreFoundation
import Foundation
import HTTPTypes
import OpenAPIRuntime

struct FormEncodingMiddleware: ClientMiddleware {
    private static let formURLEncodedAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
    )

    // These ID lists use comma-separated form values in java-slack-sdk.
    private static let commaSeparatedFields: [String: Set<String>] = [
        "adminAppsMcpServersPermissionsSet": ["user_ids", "usergroup_ids"],
        "adminSlackbotSkillsList": ["creator_ids"],
        "adminSlackbotSkillsPublish": ["skill_ids"],
        "adminSlackbotSkillsSetAutoEnabled": ["usergroup_ids"],
        "adminSlackbotSkillsUnpublish": ["skill_ids"],
    ]

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let transformedRequest = try await transformToFormEncoded(request, body: body, operationID: operationID)
        return try await next(transformedRequest.request, transformedRequest.body, baseURL)
    }

    private func transformToFormEncoded(
        _ request: HTTPRequest,
        body: HTTPBody?,
        operationID: String,
    ) async throws -> (request: HTTPRequest, body: HTTPBody?) {
        // Only transform POST requests with application/json content-type
        guard request.method == .post,
              let contentType = request.headerFields[.contentType],
              contentType.contains("application/json"),
              let body else {
            return (request, body)
        }

        // Read the JSON body
        let jsonData = try await Data(collecting: body, upTo: .max)

        // Parse JSON to extract fields
        guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return (request, body)
        }

        // Convert to form-urlencoded
        let formData = try convertJSONToForm(jsonObject, commaSeparatedFields: Self.commaSeparatedFields[operationID] ?? [])
        let formBody = HTTPBody(Data(formData.utf8))

        // Update request headers
        var transformedRequest = request
        transformedRequest.headerFields[.contentType] = "application/x-www-form-urlencoded"

        return (transformedRequest, formBody)
    }

    private func convertJSONToForm(_ jsonObject: [String: Any], commaSeparatedFields: Set<String>) throws -> String {
        var formComponents: [String] = []

        for (key, value) in jsonObject {
            let formValue: String

            if commaSeparatedFields.contains(key), let ids = value as? [String] {
                formValue = ids.joined(separator: ",")
            } else if isNestedStructure(value) {
                // Convert nested objects/arrays to JSON strings
                let jsonData = try JSONSerialization.data(withJSONObject: value)
                formValue = String(data: jsonData, encoding: .utf8) ?? ""
            } else if let stringValue = value as? String {
                formValue = stringValue
            } else if let numberValue = value as? NSNumber {
                if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                    formValue = numberValue.boolValue ? "true" : "false"
                } else {
                    formValue = numberValue.stringValue
                }
            } else {
                // Fallback: convert to JSON string
                let jsonData = try JSONSerialization.data(withJSONObject: value)
                formValue = String(data: jsonData, encoding: .utf8) ?? ""
            }

            // URL encode both key and value
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowedCharacters) ?? key
            let encodedValue = formValue.addingPercentEncoding(withAllowedCharacters: Self.formURLEncodedAllowedCharacters) ?? formValue

            formComponents.append("\(encodedKey)=\(encodedValue)")
        }

        return formComponents.joined(separator: "&")
    }

    private func isNestedStructure(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any]
    }
}
