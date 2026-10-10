#!/usr/bin/env ruby
# frozen_string_literal: true

# Decodes the java-slack-sdk fixture of every Web API method (all/openapi.json: 334 methods) with the types
# swift-openapi-generator emits for the Java-derived schemas, and groups the failures by cause.
#
#   1. regenerates all/openapi.json + all/cfg.yaml from the Java sources (committed; `git diff all` shows drift)
#   2. generates the Swift types into all/pkg (git-ignored build output) and builds the DecodeAll executable
#   3. writes the fixtures to all/out/fixtures, minus the recorder's placeholders (java_placeholders.rb)
#   4. runs DecodeAll over them and prints the success count and the failures grouped by error kind + path
#
# Usage: decode_all.rb [--raw]    --raw keeps the fixtures untouched, to see what the placeholders break
# Needs what generate.sh needs (bundle install, submodules, `swift build --package-path Tools`).

require "json"
require "fileutils"
require "open3"
require_relative "java_placeholders"

HERE = __dir__
ROOT = File.expand_path("../..", HERE)
FIXTURES = File.join(ROOT, "vendor/java-slack-sdk/json-logs/samples/api")
ALL = File.join(HERE, "all")
PKG = File.join(ALL, "pkg")
OUT = File.join(ALL, "out/fixtures")
RAW = ARGV.include?("--raw")

def sh(*command, **options)
  system(*command, **options) or abort "failed: #{command.join(" ")}"
end

# Every fixture is a method; the ones without a Response class (oauth.*, rtm.*, ...) are skipped by gen_openapi.rb.
methods = Dir.glob("*.json", base: FIXTURES).map { File.basename(_1, ".json") }.sort

sh({ "SLACKBLOCKKIT_DIR" => File.join(ROOT, "Sources/SlackBlockKit") }, "bundle", "exec", "ruby", File.join(HERE, "gen_openapi.rb"),
   File.join(ROOT, "vendor/java-slack-sdk"), File.join(ALL, "openapi.json"), File.join(ALL, "cfg.yaml"), *methods, out: File::NULL)

document = JSON.parse(File.read(File.join(ALL, "openapi.json"), encoding: "UTF-8"))
decoders = document["paths"].map do |path, item|
  type = item["post"]["responses"]["200"]["content"]["application/json"]["schema"]["$ref"].split("/").last
  %(    "#{path[1..]}": { _ = try JSONDecoder().decode(S.#{type}.self, from: $0) },)
end

FileUtils.rm_rf(File.join(PKG, "Sources"))
FileUtils.mkdir_p([File.join(PKG, "Sources/AllTypes"), File.join(PKG, "Sources/DecodeAll")])
File.write(File.join(PKG, "Package.swift"), <<~SWIFT)
  // swift-tools-version: 6.2
  import PackageDescription

  let package = Package(
      name: "AllProto",
      platforms: [.macOS(.v14)],
      dependencies: [
          .package(path: "../../../..", traits: []),
          .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.11.0"),
      ],
      targets: [
          .target(name: "AllTypes", dependencies: [
              .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
              .product(name: "SlackBlockKit", package: "swift-slack"),
          ]),
          .executableTarget(name: "DecodeAll", dependencies: ["AllTypes"]),
      ]
  )
SWIFT
File.write(File.join(PKG, "Sources/DecodeAll/main.swift"), <<~SWIFT)
  import Foundation
  import AllTypes

  // Usage: DecodeAll <dir with <method>.json>; prints "<method>\\tOK" or "<method>\\tFAIL\\t<kind>\\t<path>[\\t<detail>]"
  typealias S = Components.Schemas
  let decoders: [String: (Data) throws -> Void] = [
  #{decoders.join("\n")}
  ]

  func path(_ c: DecodingError.Context) -> String {
      c.codingPath.map { $0.intValue.map { _ in "[]" } ?? ".\\($0.stringValue)" }.joined()
  }
  let dir = URL(fileURLWithPath: CommandLine.arguments[1])
  for file in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where file.hasSuffix(".json") {
      let method = String(file.dropLast(5))
      guard let decode = decoders[method] else { continue }
      let data = try Data(contentsOf: dir.appendingPathComponent(file))
      do { try decode(data); print("\\(method)\\tOK") }
      catch DecodingError.typeMismatch(_, let c) { print("\\(method)\\tFAIL\\ttypeMismatch\\t\\(path(c))\\t\\(c.debugDescription)") }
      catch DecodingError.keyNotFound(let k, let c) { print("\\(method)\\tFAIL\\tkeyNotFound\\t\\(path(c)).\\(k.stringValue)") }
      catch DecodingError.valueNotFound(_, let c) { print("\\(method)\\tFAIL\\tvalueNotFound\\t\\(path(c))") }
      catch DecodingError.dataCorrupted(let c) { print("\\(method)\\tFAIL\\tdataCorrupted\\t\\(path(c))\\t\\(c.debugDescription)") }
      catch { print("\\(method)\\tFAIL\\tother\\t\\(error)") }
  }
SWIFT
sh File.join(ROOT, "Tools/.build/debug/swift-openapi-generator"), "generate", "--config", File.join(ALL, "cfg.yaml"),
   "--output-directory", File.join(PKG, "Sources/AllTypes"), File.join(ALL, "openapi.json")
sh "swift", "build", "--package-path", PKG, "--product", "DecodeAll"

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)
stripped = 0
block_kit = 0
document["paths"].each_key do |path|
  method = path.delete_prefix("/")
  source = File.join(FIXTURES, "#{method}.json")
  destination = File.join(OUT, "#{method}.json")
  if RAW
    FileUtils.cp(source, destination)
  else
    removed, replaced = JavaPlaceholders.write_stripped_fixture(source, destination, method, document)
    stripped += removed
    block_kit += replaced
  end
end

output, = Open3.capture2(File.join(PKG, ".build/debug/DecodeAll"), OUT)
Result = Struct.new(:method, :status, :kind, :path, :detail) do
  def failed? = status == "FAIL"
end
results = output.each_line(chomp: true).map { |line| Result.new(*line.split("\t")) }
failures, successes = results.partition(&:failed?)
puts "placeholders removed: #{RAW ? "none (--raw)" : stripped}"
puts "Block Kit placeholders replaced: #{RAW ? "none (--raw)" : block_kit}"
puts "decoded #{successes.size}/#{results.size} fixtures"
failures.group_by { [_1.kind, _1.path] }.sort_by { |cause, group| [-group.size, cause] }.each do |(kind, path), group|
  names = group.first(3).map(&:method).join(", ")
  puts "#{group.size}x #{kind} #{path}  (#{names}#{", ..." if group.size > 3})"
  puts "     #{group.first.detail}" if group.first.detail
end
