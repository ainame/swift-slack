import Foundation
import PackagePlugin

@main
struct SwiftFormatPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let swiftformatTool = try context.tool(named: "swiftformat")
        let forwardedArguments = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments

        let process = Process()
        process.executableURL = swiftformatTool.url
        process.currentDirectoryURL = context.package.directoryURL
        process.arguments = forwardedArguments

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw SwiftFormatPluginError.nonZeroExit(status: process.terminationStatus)
        }
    }
}

enum SwiftFormatPluginError: LocalizedError {
    case nonZeroExit(status: Int32)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(status):
            return "swiftformat exited with status \(status)"
        }
    }
}
