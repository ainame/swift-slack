import Foundation

// Usage: Harness <responses_dir> <report.json>
// Decodes each saved response with swift-slack's generated type. On success, re-encodes it and lists
// the JSON paths present in the live payload but lost in the round trip (fields the Swift type drops).

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
    let method = String(file.dropLast(5))
    guard let decode = decoders[method] else { continue }
    let data = try Data(contentsOf: dir.appendingPathComponent(file))
    let live = try JSONSerialization.jsonObject(with: data)
    if (live as? [String: Any])?["ok"] as? Bool != true { report[method] = ["skipped": "ok=false"]; continue }
    do {
        let value = try decode(data)
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        var before = Set<String>(), after = Set<String>()
        paths(live, into: &before); paths(reencoded, into: &after)
        let dropped = before.subtracting(after).filter { p in !before.contains(where: { p.hasPrefix($0 + ".") && !after.contains($0) }) }
        report[method] = ["decoded": true, "dropped": dropped.sorted()]
    } catch {
        report[method] = ["decoded": false, "error": describe(error)]
    }
}
let out = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try out.write(to: URL(fileURLWithPath: args[2]))
let failed = report.filter { ($0.value as? [String: Any])?["decoded"] as? Bool == false }.keys.sorted()
print("decoded \(report.count - failed.count)/\(report.count); failures: \(failed)")
