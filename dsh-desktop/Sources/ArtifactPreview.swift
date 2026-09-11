import AppKit
import Foundation
import WebKit

enum ArtifactBridgeError: LocalizedError {
    case invalidSession
    case missingPath
    case unsafePath
    case notFound
    case tooLarge
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidSession: return "invalid session id"
        case .missingPath: return "missing artifact path"
        case .unsafePath: return "artifact path escaped the session directory"
        case .notFound: return "artifact not found"
        case .tooLarge: return "artifact is too large to preview"
        case .unreadable: return "artifact could not be read"
        }
    }
}

final class ArtifactSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "dsh-artifact"
    private let fileManager = FileManager.default

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            guard let url = task.request.url, url.scheme == Self.scheme else {
                throw ArtifactBridgeError.notFound
            }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let route = components?.host ?? ""

            switch route {
            case "list":
                let session = try sessionParam(components)
                let files = try listFiles(session: session)
                finish(task, data: try Self.jsonData(["files": files]), status: 200, mime: "application/json")
            case "read":
                let session = try sessionParam(components)
                let relativePath = try pathParam(components)
                let file = try artifactFile(session: session, relativePath: relativePath)
                guard fileManager.fileExists(atPath: file.path) else { throw ArtifactBridgeError.notFound }
                let fileData = try safeRead(file)
                let text = String(data: fileData, encoding: .utf8) ?? String(data: fileData, encoding: .isoLatin1) ?? ""
                finish(task, data: Data(text.utf8), status: 200, mime: "text/plain; charset=utf-8")
            case "open":
                let session = try sessionParam(components)
                let relativePath = try pathParam(components)
                let file = try artifactFile(session: session, relativePath: relativePath)
                guard fileManager.fileExists(atPath: file.path) else { throw ArtifactBridgeError.notFound }
                NSWorkspace.shared.open(file)
                finish(task, data: try Self.jsonData(["ok": true]), status: 200, mime: "application/json")
            case "reveal":
                let session = try sessionParam(components)
                let relativePath = try pathParam(components)
                let file = try artifactFile(session: session, relativePath: relativePath)
                guard fileManager.fileExists(atPath: file.path) else { throw ArtifactBridgeError.notFound }
                NSWorkspace.shared.activateFileViewerSelecting([file])
                finish(task, data: try Self.jsonData(["ok": true]), status: 200, mime: "application/json")
            case "status":
                finish(task, data: try Self.jsonData(["ok": true, "root": AppPaths.artifactsRoot]), status: 200, mime: "application/json")
            default:
                throw ArtifactBridgeError.notFound
            }
        } catch {
            finish(task, data: Data(("{\"error\":\"" + escapeJson((error as? ArtifactBridgeError)?.errorDescription ?? error.localizedDescription) + "\"}").utf8), status: 400, mime: "application/json")
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func sessionParam(_ components: URLComponents?) throws -> String {
        guard let value = components?.queryItems?.first(where: { $0.name == "session" })?.value,
              value.range(of: #"^[A-Za-z0-9._-]{1,200}$"#, options: .regularExpression) != nil else {
            throw ArtifactBridgeError.invalidSession
        }
        return value
    }

    private func pathParam(_ components: URLComponents?) throws -> String {
        guard let value = components?.queryItems?.first(where: { $0.name == "path" })?.value,
              !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("..") else {
            throw ArtifactBridgeError.missingPath
        }
        return value
    }

    private func sessionDirectory(session: String) throws -> URL {
        let root = URL(fileURLWithPath: AppPaths.artifactsRoot, isDirectory: true).standardizedFileURL
        return root.appendingPathComponent(session, isDirectory: true).standardizedFileURL
    }

    private func artifactFile(session: String, relativePath: String) throws -> URL {
        let base = try sessionDirectory(session: session)
        let candidate = base.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        let realBase = base.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let realCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        guard realCandidate.hasPrefix(realBase) else { throw ArtifactBridgeError.unsafePath }
        return candidate
    }

    private func safeRead(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ArtifactBridgeError.unreadable }
        guard (values.fileSize ?? 0) <= 5_000_000 else { throw ArtifactBridgeError.tooLarge }
        do {
            return try Data(contentsOf: file)
        } catch {
            throw ArtifactBridgeError.unreadable
        }
    }

    private func listFiles(session: String) throws -> [[String: Any]] {
        let base = try sessionDirectory(session: session)
        guard fileManager.fileExists(atPath: base.path) else { return [] }
        var files: [[String: Any]] = []

        if let enumerator = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                let rel = url.path.replacingOccurrences(of: base.path + "/", with: "")
                let date = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                files.append(["rel": rel, "size": values?.fileSize ?? 0, "modified": date])
            }
        }

        files.sort {
            let left = $0["rel"] as? String ?? ""
            let right = $1["rel"] as? String ?? ""
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return files
    }

    private func finish(_ task: WKURLSchemeTask, data: Data, status: Int, mime: String) {
        guard let url = task.request.url else {
            task.didFailWithError(ArtifactBridgeError.notFound)
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET",
                "Cache-Control": "no-store",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func jsonData(_ value: Any) throws -> Data {
        if JSONSerialization.isValidJSONObject(value) {
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        }
        return Data()
    }
}

private func escapeJson(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}
