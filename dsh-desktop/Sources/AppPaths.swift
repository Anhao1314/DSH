import Foundation

/// 只读派生路径。所有取值来自 ProjectLocator，不再硬编码任何个人路径。
enum AppPaths {
    static var projectRoot: String? {
        ProjectLocator.shared.cachedRoot?.path
    }

    static var orbDir: String? {
        projectRoot.map { $0 + "/orbstack" }
    }

    static var artifactsRoot: String {
        if let root = projectRoot { return root + "/dsh-home/artifacts" }
        // 工程未定位时给一个必然不存在的安全路径：所有产物请求都会 404，且仍受目录校验约束。
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DSHTeam-unresolved-artifacts", isDirectory: true).path
    }

    static var consoleHome: String? {
        projectRoot.map { $0 + "/dsh-home/console" }
    }
}
