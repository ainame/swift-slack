import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct UploadedFile: Encodable, Sendable {
    let fileID: String
    let permalink: String?
    var slackFile: [String: String] {
        ["id": fileID]
    }

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case permalink
        case slackFile = "slack_file"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileID, forKey: .fileID)
        try container.encodeIfPresent(permalink, forKey: .permalink)
        try container.encode(slackFile, forKey: .slackFile)
    }
}

struct WorkspaceUpload: Sendable {
    static let maximumBytes = 20 * 1024 * 1024
    let filename: String
    let data: Data

    static func read(path: String, workspace: String) throws -> Self {
        let root = URL(filePath: workspace).standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(filePath: path, relativeTo: root.appendingPathComponent("", isDirectory: true)).standardizedFileURL
        guard !path.isEmpty, candidate.path.hasPrefix(root.path + "/") else {
            throw AgentToolError(description: "Upload path must be inside the current worktree.")
        }
        let components = String(candidate.path.dropFirst(root.path.count + 1)).split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0 == ".git" || $0 == ".env" || $0.hasPrefix(".env.") }) else {
            throw AgentToolError(description: "Git metadata and environment files cannot be uploaded.")
        }
        // Walk directory descriptors, refusing symlinks at every level. An agent changing a parent
        // while we open the file cannot redirect the read outside its worktree.
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw AgentToolError(description: "Cannot open the worktree for upload.") }
        defer { close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw AgentToolError(description: "Upload directories must exist and cannot be symlinks.") }
            close(directory)
            directory = next
        }
        let fd = openat(directory, components.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw AgentToolError(description: "Upload file must exist and cannot be a symlink.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= maximumBytes else {
            throw AgentToolError(description: "Upload a non-empty regular file of at most 20 MiB.")
        }
        var data = Data()
        while data.count <= maximumBytes {
            guard let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw AgentToolError(description: "Upload a non-empty regular file of at most 20 MiB.")
        }
        return Self(filename: components.last!, data: data)
    }
}

/// Upload raw bytes without Slack authentication headers, cookies, redirects, or leaking signed URLs.
enum SlackFileTransfer {
    static func validate(_ url: URL) throws {
        guard url.scheme == "https", url.host == "files.slack.com", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else {
            throw AgentToolError(description: "Slack returned an unsupported upload destination.")
        }
    }

    static func send(to url: URL, data: Data) async throws {
        try validate(url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await session.upload(for: request, from: data)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw AgentToolError(description: "Slack file transfer failed; the file was not shared.")
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw AgentToolError(description: "Slack file transfer failed; the file was not shared. Retry upload_file.") }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
