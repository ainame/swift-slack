#if SocketMode
import SlackClient

extension Slack {
    package func openSocketModeConnection() async throws -> String {
        guard let appToken = clientConfiguration.appToken, !appToken.isEmpty else {
            throw Error.genericError("apps.connections.open requires an app-level token with connections:write")
        }
        await setToken(appToken)
        do {
            let response = try await client.appsConnectionsOpen(body: .json(.init())).ok.body.json
            await setToken(clientConfiguration.token)
            guard response.ok else {
                throw Error.genericError("apps.connections.open failed: \(response.error ?? "unknown_error")")
            }
            guard let url = response.url, !url.isEmpty else {
                throw Error.genericError("apps.connections.open succeeded but returned no connection URL")
            }
            return url
        } catch {
            // A transport or decoding failure must not leave subsequent Web API calls using the app token.
            await setToken(clientConfiguration.token)
            throw error
        }
    }
}
#endif
