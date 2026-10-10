import Foundation
@testable import SlackApp
import Testing

/// Set by scripts/check_fixtures.rb, which preprocesses the upstream java-slack-sdk fixtures.
private let fixturesDirectory = ProcessInfo.processInfo.environment["SLACK_FIXTURES_DIR"]

@Suite(.enabled(if: fixturesDirectory != nil, "Run scripts/check_fixtures.rb to decode the upstream fixtures"))
struct FixtureDecodingTests {
    /// Each fixture is named after the event type it must decode to, e.g. MessageChangedEvent.json.
    @Test func everyGeneratedEventDecodesItsUpstreamFixture() throws {
        let directory = URL(fileURLWithPath: try #require(fixturesDirectory)).appendingPathComponent("events")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
        #expect(!names.isEmpty)

        var failures: [String] = []
        for name in names {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
            do {
                let event = try JSONDecoder().decode(Event.self, from: data)
                let decoded = event.payload.map { String(describing: type(of: $0)) } ?? "\(event)"
                if decoded != name {
                    failures.append("\(name): decoded as \(decoded)")
                }
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(names.count) fixtures failed:\n\(failures.joined(separator: "\n"))")
    }
}
