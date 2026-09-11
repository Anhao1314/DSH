import Foundation
import AppKit

/// 容器栈状态机（显式阶段，每步带超时与日志尾巴）。
///
/// `idle → checkingOrb → startingOrb → composeUp → waitingHealth → readingToken → connecting → ready`
/// 任一步失败进入 `failed(StackError)`，日志尾巴放在 `logTail` 供失败面板展开。
///
/// 每次 start/restart 都会把代际 +1：旧流水线在下一个检查点看到自己过期就安静退出，
/// 因此「等就绪卡住时点重启」也能立刻生效，而不是被 busy 挡掉。
///
/// token 只存在于内存与 Keychain：读取后立即写入 Keychain，且任何日志/文案都不带明文。
final class StackController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checkingOrb
        case startingOrb
        case composeUp
        case waitingHealth
        case readingToken
        case connecting
        case ready
        case failed(StackError)
    }

    /// 就绪后的派生状态：任务是否在跑（M3 的轮询会持续刷新）。
    enum Activity: Equatable { case idle, running, unknown }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusLine: String = Copy.phaseIdle
    @Published private(set) var logTail: String = ""
    @Published private(set) var transportLine: String = ""
    @Published private(set) var consoleURL: URL?
    @Published private(set) var activity: Activity = .unknown

    static let base = "http://127.0.0.1:3081"

    private let engine = DockerEngine()
    private let queue = DispatchQueue(label: "local.dsh.stack", qos: .userInitiated)
    private let stateLock = NSLock()
    private var generation = 0
    private var token: String?

    // MARK: - 入口

    func start() { enqueue { generation in self.fullPipeline(generation) } }

    func restartContainer() { enqueue { generation in self.restartPipeline(generation) } }

    func stopContainer() {
        enqueue { generation in
            guard let root = ProjectLocator.shared.resolve() ?? ProjectLocator.shared.cachedRoot else { return }
            self.publish(.idle, Copy.phaseIdle, generation)
            _ = self.engine.composeStop(orbDir: root.path + "/orbstack")
            self.publish(.idle, "容器已停止", generation)
        }
    }

    /// 点「下载 OrbStack」时调用。
    static func openOrbStackDownload() {
        if let url = URL(string: StackError.orbStackDownloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func enqueue(_ work: @escaping (Int) -> Void) {
        stateLock.lock()
        generation += 1
        let current = generation
        stateLock.unlock()
        queue.async { work(current) }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return generation == self.generation
    }

    // MARK: - 流水线

    private func fullPipeline(_ generation: Int) {
        publish(.checkingOrb, Copy.phaseCheckingOrb, generation)
        guard let root = ProjectLocator.shared.resolve() ?? ProjectLocator.shared.cachedRoot else {
            fail(.projectMissing, tail: "", generation)
            return
        }

        engine.selectTransport()
        publishTransport(generation)

        if !engine.ping() {
            publish(.startingOrb, Copy.phaseStartingOrb, generation)
            guard startOrbStack(generation) else { return }
            engine.selectTransport()
            publishTransport(generation)
        }

        publish(.composeUp, Copy.phaseComposeUp, generation)
        let up = engine.composeUp(orbDir: root.path + "/orbstack")
        guard isCurrent(generation) else { return }
        if !up.ok {
            fail(.composeFailed(LogRedaction.tail(up.output, lines: 6)), tail: engine.logsTail(lines: 40), generation)
            return
        }
        finishStartup(generation)
    }

    private func restartPipeline(_ generation: Int) {
        publish(.checkingOrb, Copy.actionRestartContainer, generation)
        engine.selectTransport()
        publishTransport(generation)
        let result = engine.restart()
        guard isCurrent(generation) else { return }
        guard result.ok else {
            fail(.socketFailed("重启容器失败：\(result.detail)"), tail: engine.logsTail(lines: 40), generation)
            return
        }
        finishStartup(generation)
    }

    /// 容器已起：等待 healthy → 读 token（入 Keychain）→ 确认中继可达 → ready。
    private func finishStartup(_ generation: Int) {
        publish(.waitingHealth, Copy.phaseWaitingHealth, generation)
        guard waitForHealthy(generation) else {
            if isCurrent(generation) { fail(.healthTimeout, tail: engine.logsTail(lines: 40), generation) }
            return
        }

        publish(.readingToken, Copy.phaseReadingToken, generation)
        guard let fresh = readToken() else {
            fail(.tokenMissing, tail: engine.logsTail(lines: 40), generation)
            return
        }
        guard isCurrent(generation) else { return }
        token = fresh
        KeychainStore.saveToken(fresh)

        publish(.connecting, Copy.phaseConnecting, generation)
        guard waitForRelay(token: fresh, generation: generation) else {
            if isCurrent(generation) { fail(.relayUnreachable, tail: engine.logsTail(lines: 40), generation) }
            return
        }

        guard isCurrent(generation), let url = URL(string: Self.base + "/console?token=" + fresh) else { return }
        DispatchQueue.main.async {
            guard self.isCurrent(generation) else { return }
            self.consoleURL = url
            self.statusLine = Copy.phaseReady
            self.phase = .ready
            self.activity = .unknown
        }
    }

    // MARK: - 单步（每步都会检查代际）

    private func startOrbStack(_ generation: Int) -> Bool {
        let open = ProcessShell.run("open -a OrbStack", timeout: 10)
        if !open.ok {
            fail(.orbNotFound, tail: "", generation)
            return false
        }
        for _ in 0..<60 {
            if !isCurrent(generation) { return false }
            if engine.ping() { return true }
            Thread.sleep(forTimeInterval: 1)
            engine.selectTransport()
        }
        fail(.orbStartTimeout, tail: "", generation)
        return false
    }

    private func waitForHealthy(_ generation: Int) -> Bool {
        var stoppedPolls = 0
        for _ in 0..<45 {
            if !isCurrent(generation) { return false }
            if engine.health() == "healthy" { return true }
            // 容器根本没在跑（被外部停掉 / 起不来）时快速失败，不空等 90 秒。
            let state = engine.state()
            if state == "exited" || state == "dead" || state == "created" || state == nil {
                stoppedPolls += 1
                if stoppedPolls >= 3 { return false }
            } else {
                stoppedPolls = 0
            }
            Thread.sleep(forTimeInterval: 2)
        }
        return false
    }

    private func readToken() -> String? {
        let logs = engine.logsTail(lines: 400)
        guard let regex = try? NSRegularExpression(pattern: "token=([A-Za-z0-9_\\-]{8,})") else { return nil }
        let range = NSRange(logs.startIndex..<logs.endIndex, in: logs)
        guard let match = regex.matches(in: logs, range: range).last,
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: logs) else { return nil }
        let value = String(logs[tokenRange])
        return value.isEmpty ? nil : value
    }

    private func waitForRelay(token: String, generation: Int) -> Bool {
        guard let url = URL(string: Self.base + "/console?token=" + token) else { return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        for _ in 0..<10 {
            if !isCurrent(generation) { return false }
            let semaphore = DispatchSemaphore(value: 0)
            var ok = false
            let task = session.dataTask(with: url) { _, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode == 200 { ok = true }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 10)
            if ok { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    // MARK: - 发布

    private func publish(_ phase: Phase, _ line: String, _ generation: Int) {
        guard isCurrent(generation) else { return }
        DispatchQueue.main.async {
            guard self.isCurrent(generation) else { return }
            self.phase = phase
            self.statusLine = line
        }
    }

    private func publishTransport(_ generation: Int) {
        let description = engine.transportDescription
        guard isCurrent(generation) else { return }
        DispatchQueue.main.async {
            guard self.isCurrent(generation) else { return }
            self.transportLine = description
        }
    }

    private func fail(_ error: StackError, tail: String, _ generation: Int) {
        guard isCurrent(generation) else { return }
        let redacted = LogRedaction.tail(LogRedaction.redact(tail), lines: 40)
        DispatchQueue.main.async {
            guard self.isCurrent(generation) else { return }
            self.logTail = redacted
            self.statusLine = error.title
            self.phase = .failed(error)
        }
    }

    // MARK: - 退出

    /// Policy A：退出时同步停容器，占用归零。只操作 dsh 这一个容器。
    static func stopOnQuit() {
        guard let root = ProjectLocator.shared.resolve() ?? ProjectLocator.shared.cachedRoot else { return }
        _ = ProcessShell.run("cd \(root.path)/orbstack && docker compose stop", timeout: 25)
    }
}
