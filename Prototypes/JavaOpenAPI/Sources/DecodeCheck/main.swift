import Foundation
import JavaProtoTypes

// Usage: DecodeCheck <dir with <method>[.N].json> <report.json>
typealias S = Components.Schemas
let decoders: [String: (Data) throws -> any Encodable] = [
    "team.info": { try JSONDecoder().decode(S.TeamInfoResponse.self, from: $0) },
    "users.info": { try JSONDecoder().decode(S.UsersInfoResponse.self, from: $0) },
    "conversations.list": { try JSONDecoder().decode(S.ConversationsListResponse.self, from: $0) },
    "chat.postMessage": { try JSONDecoder().decode(S.ChatPostMessageResponse.self, from: $0) },
    "admin.conversations.getConversationPrefs": { try JSONDecoder().decode(S.AdminConversationsGetConversationPrefsResponse.self, from: $0) },
]

func paths(_ value: Any, _ prefix: String = "", into set: inout Set<String>) {
    if let dict = value as? [String: Any] {
        for (k, v) in dict { let p = prefix.isEmpty ? k : "\(prefix).\(k)"; set.insert(p); paths(v, p, into: &set) }
    } else if let array = value as? [Any] {
        for v in array { paths(v, prefix + "[]", into: &set) }
    }
}

func describe(_ error: Error) -> [String: String] {
    func path(_ c: DecodingError.Context) -> String {
        c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
    switch error {
    case let DecodingError.typeMismatch(type, c): return ["kind": "typeMismatch", "expected": "\(type)", "path": path(c), "detail": c.debugDescription]
    case let DecodingError.keyNotFound(key, c): return ["kind": "keyNotFound", "key": key.stringValue, "path": path(c), "detail": c.debugDescription]
    case let DecodingError.valueNotFound(type, c): return ["kind": "valueNotFound", "expected": "\(type)", "path": path(c), "detail": c.debugDescription]
    case let DecodingError.dataCorrupted(c): return ["kind": "dataCorrupted", "path": path(c), "detail": c.debugDescription]
    default: return ["kind": "other", "detail": "\(error)"]
    }
}

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1])
var report: [String: Any] = [:]
for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where file.hasSuffix(".json") && !file.hasPrefix("_") {
    var key = String(file.dropLast(5))
    var method = key
    if let last = method.split(separator: ".").last, Int(last) != nil { method = String(method.dropLast(last.count + 1)) }
    guard let decode = decoders[method] else { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(file))
    let live = try JSONSerialization.jsonObject(with: data)
    do {
        let value = try decode(data)
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        var before = Set<String>(), after = Set<String>()
        paths(live, into: &before); paths(reencoded, into: &after)
        let dropped = before.subtracting(after).filter { p in !before.contains(where: { p.hasPrefix($0 + ".") && !after.contains($0) }) }
        report[key] = ["decoded": true, "dropped": dropped.sorted()]
    } catch {
        report[key] = ["decoded": false, "error": describe(error)]
    }
}

// Explicit null handling
do {
    let json = #"{"ok":true,"team":{"name":null,"icon":null,"default_channels":null},"channels":null}"#.data(using: .utf8)!
    let v = try JSONDecoder().decode(S.TeamInfoResponse.self, from: json)
    report["_null_synthetic_team.info"] = ["decoded": true, "name_is_nil": v.team?.name == nil]
} catch { report["_null_synthetic_team.info"] = ["decoded": false, "error": describe(error)] }
do {
    let json = #"{"ok":true,"channels":[{"id":"C1","parent_conversation":null,"topic":null}]}"#.data(using: .utf8)!
    let v = try JSONDecoder().decode(S.ConversationsListResponse.self, from: json)
    let re = String(data: try JSONEncoder().encode(v), encoding: .utf8)!
    report["_null_synthetic_conversations.list"] = ["decoded": true, "reencoded": re]
} catch { report["_null_synthetic_conversations.list"] = ["decoded": false, "error": describe(error)] }

let out = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try out.write(to: URL(fileURLWithPath: args[2]))
let failed = report.filter { ($0.value as? [String: Any])?["decoded"] as? Bool == false }.keys.sorted()
print("decoded \(report.count - failed.count)/\(report.count); failures: \(failed)")
