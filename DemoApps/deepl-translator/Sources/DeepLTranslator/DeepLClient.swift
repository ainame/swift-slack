import AsyncHTTPClient
import Foundation
import Logging
import NIOCore

public struct DeepLClient: Sendable {
    private let httpClient: HTTPClient
    private let authKey: String
    private let apiBaseURL: String
    private let logger = Logger(label: "DeepLClient")

    public init(httpClient: HTTPClient, authKey: String, isFreePlan: Bool = false) {
        self.httpClient = httpClient
        self.authKey = authKey
        apiBaseURL = isFreePlan ? "https://api-free.deepl.com/v2" : "https://api.deepl.com/v2"
    }

    public func translate(text: String, targetLanguage: String) async throws -> String? {
        let preprocessedText = preprocessSlackMarkup(text)

        // Create simple request with only required parameters
        let requestBody = TranslateRequest(
            text: [preprocessedText],
            targetLang: targetLanguage.uppercased(),
            tagHandling: nil,
            ignoreTags: nil,
        )

        let url = "\(apiBaseURL)/translate"

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Authorization", value: "DeepL-Auth-Key \(authKey)")
        request.headers.add(name: "Content-Type", value: "application/json")

        // Encode JSON body
        let bodyData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(ByteBuffer(data: bodyData))

        // Execute request
        let response = try await httpClient.execute(request, timeout: .seconds(30))

        // Collect response body
        let body = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        let responseData = Data(buffer: body)

        if response.status != .ok {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "Unable to decode error"
            logger.error("DeepL API Error", metadata: [
                "status": "\(response.status.code)",
                "response": "\(errorBody)",
            ])
            throw DeepLError.apiError(statusCode: Int(response.status.code))
        }

        // Decode response
        let translationResponse = try JSONDecoder().decode(TranslateResponse.self, from: responseData)
        guard let translation = translationResponse.translations.first else {
            logger.error("No translation in response")
            return nil
        }

        return postprocessSlackMarkup(translation.text)
    }
}

// MARK: - Slack Markup Processing

extension DeepLClient {
    private func preprocessSlackMarkup(_ text: String) -> String {
        var processed = text

        // Handle Slack special syntax with regex replacements
        // Convert <@U123|username> and <#C123|channel> to safe tags
        processed = processed.replacingOccurrences(
            of: #"<([@#][^>|]+)(?:\|([^>]+))?>"#,
            with: "<mrkdwn>$1</mrkdwn>",
            options: .regularExpression,
        )

        // Handle subteam mentions
        processed = processed.replacingOccurrences(
            of: #"<!subteam\^[^>|]+(?:\|([^>]+))?>"#,
            with: "@[subteam mention removed]",
            options: .regularExpression,
        )

        // Handle date formatting
        processed = processed.replacingOccurrences(
            of: #"<(!date[^>]+)>"#,
            with: "<mrkdwn>$1</mrkdwn>",
            options: .regularExpression,
        )

        // Handle special mentions (!here, !channel, !everyone)
        processed = processed.replacingOccurrences(
            of: #"<!([^>|]+)(?:\|([^>]+))?>"#,
            with: "<ignore>@$1</ignore>",
            options: .regularExpression,
        )

        // Handle formatted links
        processed = processed.replacingOccurrences(
            of: #"<([^>|]+)\|([^>]+)>"#,
            with: #"<a href="$1">$2</a>"#,
            options: .regularExpression,
        )

        // Handle raw links
        processed = processed.replacingOccurrences(
            of: #"<([^>|]+)>"#,
            with: "<mrkdwn>$1</mrkdwn>",
            options: .regularExpression,
        )

        // Handle emoji
        processed = processed.replacingOccurrences(
            of: #":([a-z0-9_+-]+):"#,
            with: "<emoji>$1</emoji>",
            options: .regularExpression,
        )

        return processed
    }

    private func postprocessSlackMarkup(_ text: String) -> String {
        var processed = text

        // Restore emoji
        processed = processed.replacingOccurrences(
            of: #"<emoji>([a-z0-9_+-]+)</emoji>"#,
            with: ":$1:",
            options: .regularExpression,
        )

        // Restore mrkdwn tags
        processed = processed.replacingOccurrences(
            of: #"<mrkdwn>([^<]+)</mrkdwn>"#,
            with: "<$1>",
            options: .regularExpression,
        )

        // Restore links from <a> tags
        processed = processed.replacingOccurrences(
            of: #"<a href="([^"]+)">([^<]+)</a>"#,
            with: "<$1|$2>",
            options: .regularExpression,
        )

        // Restore ignore tags
        processed = processed.replacingOccurrences(
            of: #"<ignore>([^<]+)</ignore>"#,
            with: "$1",
            options: .regularExpression,
        )

        return processed
    }
}

// MARK: - Types

struct TranslateRequest: Codable {
    let text: [String]
    let targetLang: String
    let tagHandling: String?
    let ignoreTags: [String]?

    private enum CodingKeys: String, CodingKey {
        case text
        case targetLang = "target_lang"
        case tagHandling = "tag_handling"
        case ignoreTags = "ignore_tags"
    }
}

struct TranslateResponse: Codable {
    let translations: [Translation]
}

struct Translation: Codable {
    let detectedSourceLanguage: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case detectedSourceLanguage = "detected_source_language"
        case text
    }
}

enum DeepLError: Error {
    case apiError(statusCode: Int)
}
