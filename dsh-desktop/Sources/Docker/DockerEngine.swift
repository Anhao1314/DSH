import Foundation

/// Docker Engine 客户端：unix socket 直连优先，失败降级到 docker CLI。
/// 只按名字操作 `dsh` 这一个容器；绝不遍历、清理或停止其它容器。
/// 所有方法同步阻塞，必须在后台队列调用。
final class DockerEngine {
    enum Transport: Equatable {
        case socket(String)
        case cli
    }

    static let containerName = "dsh"
    /// 已实测：OrbStack 用第一个；`/var/run/docker.sock` 是指向它的符号链接。
    static let socketCandidates: [String] = [
        NSHomeDirectory() + "/.orbstack/run/docker.sock",
        "/var/run/docker.sock",
    ]

    private let lock = NSLock()
    private var _transport: Transport = .cli

    var transport: Transport {
        lock.lock(); defer { lock.unlock() }
        return _transport
    }

    var transportDescription: String {
        switch transport {
        case .socket(let path): return "Engine API · \(path)"
        case .cli: return "docker CLI（降级）"
        }
    }

    // MARK: - 通道选择

    /// 依序探测候选 socket，命中即固定；否则用 CLI。
    @discardableResult
    func selectTransport() -> Transport {
        for path in Self.socketCandidates where FileManager.default.fileExists(atPath: path) {
            if let response = try? UnixSocketHTTP.request(socketPath: path, path: "/_ping", timeout: 3),
               response.status == 200 {
                lock.lock(); _transport = .socket(path); lock.unlock()
                return transport
            }
        }
        lock.lock(); _transport = .cli; lock.unlock()
        return transport
    }

    // MARK: - 探测

    func ping() -> Bool {
        switch transport {
        case .socket(let path):
            if let response = try? UnixSocketHTTP.request(socketPath: path, path: "/_ping", timeout: 5),
               response.status == 200 { return true }
            return false
        case .cli:
            return ProcessShell.run("docker info --format '{{.ServerVersion}}' >/dev/null 2>&1", timeout: 8).ok
        }
    }

    func state(_ name: String = containerName) -> String? {
        switch transport {
        case .socket(let path):
            guard let response = try? UnixSocketHTTP.request(socketPath: path, path: "/containers/\(name)/json", timeout: 6),
                  response.status == 200,
                  let inspect = try? JSONDecoder().decode(DockerContainerInspect.self, from: response.body) else { return nil }
            return inspect.state?.status
        case .cli:
            let result = ProcessShell.run("docker inspect -f '{{.State.Status}}' \(name) 2>/dev/null", timeout: 8)
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    func health(_ name: String = containerName) -> String? {
        switch transport {
        case .socket(let path):
            guard let response = try? UnixSocketHTTP.request(socketPath: path, path: "/containers/\(name)/json", timeout: 6),
                  response.status == 200,
                  let inspect = try? JSONDecoder().decode(DockerContainerInspect.self, from: response.body) else { return nil }
            return inspect.state?.health?.status
        case .cli:
            let result = ProcessShell.run(
                "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \(name) 2>/dev/null",
                timeout: 8
            )
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    // MARK: - 生命周期

    @discardableResult
    func start(_ name: String = containerName) -> (ok: Bool, detail: String) {
        post(path: "/containers/\(name)/start", timeout: 30, cli: "docker start \(name)", cliTimeout: 30)
    }

    @discardableResult
    func stop(_ name: String = containerName, graceSeconds: Int = 20) -> (ok: Bool, detail: String) {
        post(
            path: "/containers/\(name)/stop?t=\(graceSeconds)",
            timeout: 40,
            cli: "docker stop -t \(graceSeconds) \(name)",
            cliTimeout: 45
        )
    }

    @discardableResult
    func restart(_ name: String = containerName, graceSeconds: Int = 20) -> (ok: Bool, detail: String) {
        post(
            path: "/containers/\(name)/restart?t=\(graceSeconds)",
            timeout: 90,
            cli: "docker restart -t \(graceSeconds) \(name)",
            cliTimeout: 90
        )
    }

    private func post(path: String, timeout: TimeInterval, cli: String, cliTimeout: TimeInterval) -> (ok: Bool, detail: String) {
        switch transport {
        case .socket(let socketPath):
            guard let response = try? UnixSocketHTTP.request(socketPath: socketPath, method: "POST", path: path, timeout: timeout) else {
                return (false, "Engine API 请求失败")
            }
            if (200...299).contains(response.status) { return (true, "ok") }
            if response.status == 304 { return (true, "已经是目标状态") } // already started/stopped
            return (false, "Engine API 返回 \(response.status)：\(LogRedaction.tail(response.bodyText, lines: 3))")
        case .cli:
            let result = ProcessShell.run(cli, timeout: cliTimeout)
            return (result.ok, result.ok ? "ok" : result.output)
        }
    }

    /// compose 只能走 CLI（Engine API 没有等价物）；输出进启动日志缓冲。
    func composeUp(orbDir: String, timeout: TimeInterval = 90) -> ProcessShell.Result {
        ProcessShell.run("cd \(orbDir) && docker compose up -d", timeout: timeout)
    }

    func composeStop(orbDir: String, timeout: TimeInterval = 25) -> ProcessShell.Result {
        ProcessShell.run("cd \(orbDir) && docker compose stop", timeout: timeout)
    }

    // MARK: - 观测

    /// CPU% 用两次采样（间隔 1s）的增量计算；内存取 usage(减 cache) / limit。
    /// 容器真实上限：HostConfig 的 NanoCpus / Memory（override 文件可能改过 compose 的字面值）。
    func limits(_ name: String = containerName) -> ContainerLimits? {
        switch transport {
        case .socket(let path):
            guard let response = try? UnixSocketHTTP.request(socketPath: path, path: "/containers/\(name)/json", timeout: 6),
                  response.status == 200,
                  let inspect = try? JSONDecoder().decode(DockerContainerInspect.self, from: response.body),
                  let host = inspect.hostConfig else { return nil }
            return ContainerLimits(
                cpus: Double(host.nanoCpus ?? 0) / 1_000_000_000,
                memoryBytes: host.memory ?? 0
            )
        case .cli:
            let result = ProcessShell.run(
                "docker inspect -f '{{.HostConfig.NanoCpus}}|{{.HostConfig.Memory}}' \(name) 2>/dev/null",
                timeout: 8
            )
            let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            guard parts.count == 2 else { return nil }
            return ContainerLimits(
                cpus: (Double(parts[0]) ?? 0) / 1_000_000_000,
                memoryBytes: UInt64(parts[1]) ?? 0
            )
        }
    }

    func stats(_ name: String = containerName) -> ContainerMetrics? {
        switch transport {
        case .socket(let path):
            guard let first = statsSample(socketPath: path, name: name) else { return nil }
            Thread.sleep(forTimeInterval: 1.0)
            guard let second = statsSample(socketPath: path, name: name) else { return nil }
            return Self.metrics(previous: first, current: second)
        case .cli:
            return cliStats(name)
        }
    }

    private func statsSample(socketPath: String, name: String) -> DockerStatsSample? {
        guard let response = try? UnixSocketHTTP.request(
            socketPath: socketPath,
            path: "/containers/\(name)/stats?stream=false",
            timeout: 8
        ), response.status == 200 else { return nil }
        return try? JSONDecoder().decode(DockerStatsSample.self, from: response.body)
    }

    static func metrics(previous: DockerStatsSample, current: DockerStatsSample) -> ContainerMetrics {
        let cpuDelta = Double(current.cpuStats?.cpuUsage?.totalUsage ?? 0) - Double(previous.cpuStats?.cpuUsage?.totalUsage ?? 0)
        let systemDelta = Double(current.cpuStats?.systemCpuUsage ?? 0) - Double(previous.cpuStats?.systemCpuUsage ?? 0)
        let onlineCPUs = Double(
            current.cpuStats?.onlineCpus
            ?? current.cpuStats?.cpuUsage?.percpuUsage?.count
            ?? 1
        )
        let cpuPercent: Double
        if systemDelta > 0, cpuDelta >= 0 {
            cpuPercent = max(0, min(100 * onlineCPUs, cpuDelta / systemDelta * onlineCPUs * 100))
        } else {
            cpuPercent = 0
        }

        let usage = current.memoryStats?.usage ?? 0
        let cache = current.memoryStats?.stats?["cache"] ?? current.memoryStats?.stats?["inactive_file"] ?? 0
        let limit = current.memoryStats?.limit ?? 0
        return ContainerMetrics(
            cpuPercent: cpuPercent,
            memoryBytes: usage > cache ? usage - cache : usage,
            memoryLimitBytes: limit
        )
    }

    private func cliStats(_ name: String) -> ContainerMetrics? {
        let result = ProcessShell.run(
            "docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' \(name)",
            timeout: 12
        )
        guard result.ok else { return nil }
        let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count == 2 else { return nil }
        let cpuPercent = Double(parts[0].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
        let memParts = parts[1].components(separatedBy: "/")
        guard memParts.count == 2 else { return nil }
        let used = Self.parseBytes(memParts[0])
        let limit = Self.parseBytes(memParts[1])
        return ContainerMetrics(cpuPercent: cpuPercent, memoryBytes: used, memoryLimitBytes: limit)
    }

    func logsTail(_ name: String = containerName, lines: Int = 40) -> String {
        switch transport {
        case .socket(let path):
            guard let response = try? UnixSocketHTTP.request(
                socketPath: path,
                path: "/containers/\(name)/logs?stdout=1&stderr=1&tail=\(lines)",
                timeout: 8
            ), response.status == 200 else { return "" }
            return LogRedaction.tail(UnixSocketHTTP.demuxFrames(response.body), lines: lines)
        case .cli:
            let result = ProcessShell.run("docker logs --tail \(lines) \(name) 2>&1", timeout: 12)
            return LogRedaction.tail(result.output, lines: lines)
        }
    }

    static func parseBytes(_ text: String) -> UInt64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [
            ("GiB", 1024 * 1024 * 1024), ("MiB", 1024 * 1024), ("KiB", 1024),
            ("GB", 1_000_000_000), ("MB", 1_000_000), ("kB", 1_000), ("B", 1),
        ]
        for (suffix, multiplier) in units where trimmed.hasSuffix(suffix) {
            let number = Double(trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) ?? 0
            return UInt64(number * multiplier)
        }
        return UInt64(Double(trimmed) ?? 0)
    }
}
