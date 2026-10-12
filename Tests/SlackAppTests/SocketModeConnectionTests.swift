#if SocketMode
import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import SlackApp
import SlackClient
import Testing

struct SocketModeConnectionTests {
    @Test(arguments: ["invalid_auth", "missing_scope", "not_allowed_token_type"])
    func `Slack failures preserve the API error and restore bot authentication`(code: String) async throws {
        let transport = ConnectionTransport(response: "{\"ok\":false,\"error\":\"\(code)\"}")
        let slack = Slack(transport: transport, configuration: .init(appToken: "xapp-test", token: "xoxb-test"))
        do {
            _ = try await slack.openSocketModeConnection()
            Issue.record("Accepted a failed connection")
        } catch let Slack.Error.genericError(message) {
            #expect(message == "apps.connections.open failed: \(code)")
        }
        _ = try await slack.client.authTest()
        #expect(await transport.authorization == ["Bearer xapp-test", "Bearer xoxb-test"])
    }

    @Test
    func `transport failures restore bot authentication`() async throws {
        let transport = ConnectionTransport(response: nil)
        let slack = Slack(transport: transport, configuration: .init(appToken: "xapp-test", token: "xoxb-test"))
        await #expect(throws: (any Error).self) { try await slack.openSocketModeConnection() }
        _ = try await slack.client.authTest()
        #expect(await transport.authorization == ["Bearer xapp-test", "Bearer xoxb-test"])
    }

    @Test
    func `successful connections return the URL and restore bot authentication`() async throws {
        let transport = ConnectionTransport(response: #"{"ok":true,"url":"wss://example.invalid/socket"}"#)
        let slack = Slack(transport: transport, configuration: .init(appToken: "xapp-test", token: "xoxb-test"))
        #expect(try await slack.openSocketModeConnection() == "wss://example.invalid/socket")
        _ = try await slack.client.authTest()
        #expect(await transport.authorization == ["Bearer xapp-test", "Bearer xoxb-test"])
    }

    @Test(arguments: [#"{"ok":true}"#, #"{"ok":true,"url":""}"#])
    func `successful responses still require a connection URL`(body: String) async throws {
        let transport = ConnectionTransport(response: body)
        let slack = Slack(transport: transport, configuration: .init(appToken: "xapp-test", token: "xoxb-test"))
        do {
            _ = try await slack.openSocketModeConnection()
            Issue.record("Accepted a missing connection URL")
        } catch let Slack.Error.genericError(message) {
            #expect(message == "apps.connections.open succeeded but returned no connection URL")
        }
    }

    @Test
    func `missing app tokens fail before calling Slack`() async {
        let transport = ConnectionTransport(response: nil)
        let slack = Slack(transport: transport, configuration: .init(token: "xoxb-test"))
        await #expect(throws: (any Error).self) { try await slack.openSocketModeConnection() }
        #expect(await transport.authorization.isEmpty)
    }
}

private actor ConnectionTransport: ClientTransport {
    struct Failure: Error {}
    let response: String?
    private(set) var authorization: [String] = []

    init(response: String?) {
        self.response = response
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        authorization.append(request.headerFields[.authorization] ?? "")
        let body: String
        if operationID == "appsConnectionsOpen" {
            guard let response else { throw Failure() }
            body = response
        } else {
            #expect(operationID == "authTest")
            body = #"{"ok":true}"#
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }
}
#endif
