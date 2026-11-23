import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Answers every Web API request with an empty `200 OK`, for tests that build a client they never call.
struct MockTransport: ClientTransport {
    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .ok), nil)
    }
}
