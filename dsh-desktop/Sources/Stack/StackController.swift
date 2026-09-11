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

    /// 容器被 App 之外的方式重启后 token 会轮换：重读一次凭据并换掉 consoleURL。
    /// 幂等、静默失败（读不到就保持现状，下一次轮询还会再请求）。
    func refreshToken() {
        enqueue { generation in
            self.engine.selectTransport()
            guard let fresh = self.readToken() else { return }
            guard self.isCurrent(generation) else { return }
            self.token = fresh
            KeychainStore.saveToken(fresh)
            guard let url = URL(string: Self.base + "/console?token=" + fresh) else { return }
            DispatchQueue.main.async {
                guard self.isCurrent(generation) else { return }
                self.consoleURL = url
            }
        }
    }

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
        let orbDir = root.path + "/orbstack"
        let needsBuild = engine.composeImageReference(orbDir: orbDir).map { !engine.imageExists($0) } ?? false
        if needsBuild { publish(.composeUp, Copy.phaseBuildingImage, generation) }
        let up = engine.composeUp(orbDir: orbDir, timeout: needsBuild ? 1800 : 90)
        guard isCurrent(generation) else { return }
        if !up.ok {
            fail(.composeFailed(LogRedaction.tail(up.output, lines: 6)), tail: engine.logsTail(lines: 40), generation)
            return
        }
        finishStartup(generation)
    }

    private func restartPipeline(_ generation: Int) {
        engine.selectTransport()
        publishTransport(generation)
        // 容器被删掉（docker rm / compose down）时 docker restart 必然 404：直接重跑流水线。
        if engine.state() == nil {
            fullPipeline(generation)
            return
        }
        publish(.checkingOrb, Copy.actionRestartContainer, generation)
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

    /// 容器只在启动时打印一次 token，之后会被中继访问日志顶出窗口；同时 App 重启、
    /// 容器长时间运行时也不能依赖「日志最后 400 行」。所以：
    /// 1) 分档回看（400 → 2000 → 8000 行），命中即停；
    /// 2) 仍找不到就用 Keychain 里上一次的 token 做一次真实请求验证（有效即复用）。
    private func readToken() -> String? {
        for lines in [400, 2000, 8000] {
            if let found = Self.parseToken(engine.logsTail(lines: lines)) { return found }
        }
        if let cached = KeychainStore.readToken(), relayAccepts(token: cached) { return cached }
        return nil
    }

    private static func parseToken(_ logs: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "token=([A-Za-z0-9_\\-]{8,})") else { return nil }
        let range = NSRange(logs.startIndex..<logs.endIndex, in: logs)
        guard let match = regex.matches(in: logs, range: range).last,
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: logs) else { return nil }
        let value = String(logs[tokenRange])
        return value.isEmpty ? nil : value
    }

    /// 用一次真实请求确认 token 还有效（token 不进日志、不落盘）。
    private func relayAccepts(token: String) -> Bool {
        guard let url = URL(string: Self.base + "/console-api/v1/sessions?token=" + token) else { return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        let task = session.dataTask(with: url) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { ok = true }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return ok
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
