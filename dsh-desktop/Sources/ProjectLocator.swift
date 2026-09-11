import Foundation

/// 工程目录定位 + 持久化。
///
/// 定位顺序（命中即校验，非法则继续）：
/// 1. 环境变量 `DSH_WORKBENCH_ROOT`
/// 2. `~/Library/Application Support/DSHTeam/config.json`
/// 3. App bundle 所在路径向上回溯（开发态：build/ 就在工程里）
/// 4. ~/Documents 等已知根目录下的限定深度 BFS（跳过隐藏目录与 node_modules/build 等）
///
/// 校验标准：目录内同时存在 `orbstack/compose.yaml` 与 `deepseek-harness/orbstack-relay.cjs`。
final class ProjectLocator {
    static let shared = ProjectLocator()

    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cached: URL?

    /// 最近一次定位失败的原因（诊断用，不含敏感信息）。
    private(set) var lastSearchNote: String = ""

    struct Config: Codable {
        var projectRoot: String
    }

    var configURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DSHTeam", isDirectory: true).appendingPathComponent("config.json")
    }

    private init() {}

    // MARK: - 公共接口

    /// 完整定位（带缓存）。可能较慢（磁盘扫描），请在后台线程调用。
    func resolve() -> URL? {
        lock.lock()
        if let cached { lock.unlock(); return cached }
        lock.unlock()

        let found = locate()
        if let found {
            lock.lock(); cached = found; lock.unlock()
        }
        return found
    }

    /// 只读缓存，不触发扫描。
    var cachedRoot: URL? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func validate(_ url: URL) -> Bool {
        let root = url.standardizedFileURL
        let compose = root.appendingPathComponent("orbstack/compose.yaml")
        let relay = root.appendingPathComponent("deepseek-harness/orbstack-relay.cjs")
        return fileManager.fileExists(atPath: compose.path) && fileManager.fileExists(atPath: relay.path)
    }

    func save(_ url: URL) throws {
        let root = url.standardizedFileURL
        let dir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Config(projectRoot: root.path))
        try data.write(to: configURL, options: .atomic)
        lock.lock(); cached = root; lock.unlock()
    }

    func clear() {
        try? fileManager.removeItem(at: configURL)
        lock.lock(); cached = nil; lock.unlock()
    }

    // MARK: - 定位实现

    private func locate() -> URL? {
        if let env = ProcessInfo.processInfo.environment["DSH_WORKBENCH_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if validate(url) { return url.standardizedFileURL }
            lastSearchNote = "环境变量 DSH_WORKBENCH_ROOT 指向的目录不合法"
        }

        if let url = loadSaved(), validate(url) {
            return url
        }

        for ancestor in bundleAncestors() where validate(ancestor) {
            return ancestor.standardizedFileURL
        }

        if let scanned = boundedScan() {
            return scanned
        }
        if lastSearchNote.isEmpty { lastSearchNote = "未在常见目录找到 dsh-workbench" }
        return nil
    }

    private func loadSaved() -> URL? {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return URL(fileURLWithPath: config.projectRoot, isDirectory: true)
    }

    private func bundleAncestors() -> [URL] {
        var list: [URL] = []
        var current = Bundle.main.bundleURL.standardizedFileURL
        for _ in 0..<5 {
            current = current.deletingLastPathComponent()
            if current.path == "/" { break }
            list.append(current)
        }
        return list
    }

    /// 限定深度 / 时间 / 访问量的 BFS，避免在用户目录里跑飞。
    private func boundedScan() -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let roots = ["Documents", "Desktop", "Developer", "Projects", "Code", "src", "dev"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        let maxDepth = 6
        let deadline = Date().addingTimeInterval(2.5)
        var visited = 0
        var queue: [(URL, Int)] = roots.map { ($0, 0) }

        while !queue.isEmpty {
            if Date().compare(deadline) == .orderedDescending || visited > 4000 {
                lastSearchNote = "目录扫描在限定时间内未找到工程（可手动选择）"
                return nil
            }
            let (dir, depth) = queue.removeFirst()
            visited += 1
            if validate(dir) { return dir }
            guard depth < maxDepth else { continue }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for entry in entries {
                let name = entry.lastPathComponent
                if Self.skipNames.contains(name) { continue }
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                queue.append((entry, depth + 1))
            }
        }
        return nil
    }

    private static let skipNames: Set<String> = [
        "node_modules", ".git", "build", "Library", "Pods", "DerivedData",
        ".build", ".swiftpm", "vendor", ".pnpm-store", "dist", "out",
    ]
}
