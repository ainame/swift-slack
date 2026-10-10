// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Harness",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(name: "Harness", dependencies: [.product(name: "SlackClient", package: "swift-slack")]),
    ]
)
