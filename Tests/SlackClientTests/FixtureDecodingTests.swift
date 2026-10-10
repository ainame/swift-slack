import Foundation
import Testing

/// Set by scripts/check_fixtures.rb, which preprocesses the upstream java-slack-sdk fixtures.
private let fixturesDirectory = ProcessInfo.processInfo.environment["SLACK_FIXTURES_DIR"]

@Suite(.enabled(if: fixturesDirectory != nil, "Run scripts/check_fixtures.rb to decode the upstream fixtures"))
struct FixtureDecodingTests {
    @Test func everyGeneratedResponseDecodesItsUpstreamFixture() throws {
        let directory = URL(fileURLWithPath: try #require(fixturesDirectory)).appendingPathComponent("api")
        let methods = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
        #expect(Set(methods) == Set(responseFixtureDecoders.keys))

        var failures: [String] = []
        for method in methods {
            guard let decode = responseFixtureDecoders[method] else { continue }
            let data = try Data(contentsOf: directory.appendingPathComponent("\(method).json"))
            do {
                _ = try decode(data)
            } catch {
                failures.append("\(method): \(describe(error))")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(methods.count) fixtures failed:\n\(failures.joined(separator: "\n"))")
    }
}

/// A decoding error as "<kind> at <path>: <detail>".
func describe(_ error: any Error) -> String {
    func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
    switch error {
    case let DecodingError.typeMismatch(_, context):
        return "typeMismatch at \(path(context)): \(context.debugDescription)"
    case let DecodingError.keyNotFound(key, context):
        return "keyNotFound \(key.stringValue) at \(path(context))"
    case let DecodingError.valueNotFound(_, context):
        return "valueNotFound at \(path(context))"
    case let DecodingError.dataCorrupted(context):
        return "dataCorrupted at \(path(context)): \(context.debugDescription)"
    default:
        return "\(error)"
    }
}
