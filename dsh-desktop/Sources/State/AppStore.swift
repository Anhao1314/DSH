import Foundation
import AppKit

/// 三栏工作台的数据源：轮询中继、维护选中态、给 Inspector 提供时间线 / 资源 / 产物。
///
/// 轮询纪律（M3 验收④）：
/// * 窗口可见：sessions 每 3s、容器资源每 2s、时间线每 5s（或选中项变化时立刻）。
/// * 窗口不可见且没有任务在跑：完全停表（0 请求、CPU 近零）。
/// * 窗口不可见但仍有任务在跑：只保留 5s 一次的 sessions 轻轮询，好让完成通知还能弹。
@MainActor
final class AppStore: ObservableObject {
    enum RelayPhase: Equatable {
        case idle
        case loading
        case ok
        case offline(String)
    }

    @Published private(set) var roots: [SessionRoot] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var events: [TimelineEvent] = []
    @Published private(set) var metrics: ContainerMetrics?
    @Published private(set) var limits: ContainerLimits?
    @Published private(set) var artifactCount: Int = 0
    @Published private(set) var relayPhase: RelayPhase = .idle
    @Published private(set) var lastSessionsAt: Date?
    @Published private(set) var actionNote: String?
    @Published private(set) var sessionsStale = false

    /// WebView 桥：选中某会话（失败由 Main 侧降级为整页重载）。
    var onSelectInWeb: ((String) -> Void)?
    /// 运行态变化的对外广播（M4 的通知、菜单栏共用）。
    var onRunningChanged: ((SessionRoot, Bool) -> Void)?
    var onTaskFinished: ((SessionRoot) -> Void)?
    /// 「有没有任何任务在跑」的整体翻转（⌘Q 等任务完成要用）。
    var onRunningStateChanged: ((Bool) -> Void)?
    /// 中继认定凭据失效（容器被外部重启导致 token 轮换）——请上层重读 token。
    var onTokenStale: (() -> Void)?
    /// 容器从健康变为不健康（通知用，只在翻转边沿触发一次）。
    var onContainerUnhealthy: (() -> Void)?

    private let client = RelayClient()
    private let metricsEngine = DockerEngine()
    private var tokenProvider: () -> String? = { KeychainStore.readToken() }
    private var loop: Task<Void, Never>?
    private var tick = 0
    private var visible = true
    private var visibilityOverride: Bool?
    private var runningMap: [String: Bool] = [:]
    private var lastTimelineKey = ""
    private var noteToken = 0
    private var emptyStreak = 0
    /// Docker 指标查询是否在途（慢调用不能叠加）。
    private var metricsInFlight = false
    /// 已经为「凭据失效」请求过一次重读，避免离线期间反复触发。
    private var tokenRefreshRequested = false
    /// 中继 side 的上游健康上一次观测值（只有 true→false 才通知）。
    private var upstreamWasUp: Bool?
    /// 刚创建、还没跑出投影的会话：轮询暂时看不到它，但要保住选中态。
    private var pendingSelection: (id: String, expires: Date)?

    // MARK: - 派生状态

    var selectedRoot: SessionRoot? {
        roots.first { $0.id == selectedID }
    }

    var runningRoots: [SessionRoot] { roots.filter { $0.running } }

    var isAnyRunning: Bool { !runningRoots.isEmpty }

    var currentTaskTitle: String {
        selectedRoot?.title ?? roots.first?.title ?? ""
    }

    /// 新任务刚创建、首轮还没落地时的占位行 id。
    var pendingNewTaskID: String? {
        guard let pending = pendingSelection, pending.expires > Date() else { return nil }
        return roots.contains { $0.id == pending.id } ? nil : pending.id
    }

    /// 侧边栏分组：最近 8 条 + 更早（沿用 Web 控制台习惯）。
    var recentRoots: [SessionRoot] { Array(roots.prefix(8)) }
    var olderRoots: [SessionRoot] { Array(roots.dropFirst(8)) }

    // MARK: - 生命周期

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.beat()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.tick &+= 1
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// 手动覆盖可见性（测试用）；正常情况由 `syncVisibility()` 从窗口状态推导。
    func setVisibleOverride(_ value: Bool?) {
        visibilityOverride = value
    }

    /// 窗口隐藏 / 最小化 / 最小化在 Dock：都算不可见（M3 验收④的停表条件）。
    private func syncVisibility() {
        let now = visibilityOverride ?? AppStore.windowIsVisible()
        guard now != visible else { return }
        visible = now
        if now { Task { await refresh() } }
    }

    private static func windowIsVisible() -> Bool {
        guard !NSApp.isHidden else { return false }
        return NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized
        }
    }

    func setTokenProvider(_ provider: @escaping () -> String?) {
        tokenProvider = provider
    }

    // MARK: - 心跳

    private func beat() async {
        syncVisibility()
        guard visible || isAnyRunning else { return }   // 不可见且空闲：停表
        let stride = visible ? 1 : 5

        if tick % (3 * stride) == 0 {
            await pollSessions()
        }
        if visible, tick % 2 == 1 {
            // Docker 指标走 Unix socket，单次可能 1s 以上；不能同步等它，否则会把
            // 整个心跳拖慢（实测 tick 从 1s 变 2s，sessions 从 3s 变 6–8s）。
            startMetricsPoll()
        }
        if visible, tick % 5 == 3 {
            await pollTimeline(force: false)
        }
        if visible, tick % 7 == 0 {
            recountArtifacts()
        }
        if visible, tick % 15 == 7 {
            await pollHealth()
        }
    }

    func refresh() async {
        await pollSessions()
        await pollTimeline(force: true)
        recountArtifacts()
    }

    // MARK: - 轮询

    private func pollSessions() async {
        guard let token = tokenProvider(), !token.isEmpty else { return }
        if case .idle = relayPhase { relayPhase = .loading }
        do {
            let response = try await client.sessions(token: token)
            apply(roots: response.roots)
            relayPhase = .ok
            lastSessionsAt = Date()
            tokenRefreshRequested = false
        } catch RelayError.unauthorized {
            // 容器被 App 之外的方式重启 → token 轮换 → 重读一次（只重读一次，避免打转）。
            relayPhase = .offline(Copy.relayTokenStale)
            if !tokenRefreshRequested {
                tokenRefreshRequested = true
                onTokenStale?()
            }
        } catch {
            relayPhase = .offline(error.localizedDescription)
        }
    }

    /// 中继到上游（容器内 web）的连通性：只在「好 → 坏」的边沿通知一次。
    private func pollHealth() async {
        do {
            let health = try await client.health()
            let up = health.upstreamUp
            if upstreamWasUp == true, !up { onContainerUnhealthy?() }
            upstreamWasUp = up
        } catch {
            // 中继本身不可达时不算「容器不健康」：离线态已经在 relayPhase 里表达。
        }
    }

    private func apply(roots fresh: [SessionRoot]) {
        // 容器刚重建时 session/list 会短暂给出「全部不 meaningful」的空列表；
        // 一次空响应就把界面清空体验很糟，所以连续 3 次为空才认账。
        if fresh.isEmpty && !roots.isEmpty {
            emptyStreak += 1
            sessionsStale = true
            if emptyStreak < 3 { return }
        } else {
            emptyStreak = 0
            sessionsStale = false
        }

        let previous = runningMap
        var next: [String: Bool] = [:]
        for root in fresh {
            next[root.id] = root.running
            if let was = previous[root.id], was != root.running {
                onRunningChanged?(root, root.running)
                if was && !root.running {
                    onTaskFinished?(root)
                    Notifier.shared.taskFinished(title: root.title, body: Self.finishBody(root))
                }
                if !was && root.running {
                    Notifier.shared.requestAuthorizationIfNeeded()
                }
            }
        }
        let runningNow = next.values.contains(true)
        let runningBefore = previous.values.contains(true)
        runningMap = next
        roots = fresh
        if runningNow != runningBefore { onRunningStateChanged?(runningNow) }

        if let id = selectedID, let pending = pendingSelection, pending.id == id, pending.expires > Date(),
           !fresh.contains(where: { $0.id == id }) {
            // 新任务的首轮还没进入投影：这段窗口内保住选中，别把用户刚建的任务甩掉。
        } else if let id = selectedID, !fresh.contains(where: { $0.id == id }) {
            pendingSelection = nil
            selectedID = nil
        } else if let id = selectedID, fresh.contains(where: { $0.id == id }) {
            pendingSelection = nil
        }
        if selectedID == nil, let first = fresh.first {
            select(first.id, syncWeb: true)
        }
    }

    /// 通知正文（规格 §3.4 的三种措辞 + 兜底）。
    private static func finishBody(_ root: SessionRoot) -> String {
        switch root.verdict {
        case "pass": return Copy.notifyVerdictPass
        case "fail": return Copy.notifyVerdictFail
        default: return root.children.isEmpty ? Copy.notifyTaskDone : Copy.notifyTeamDone
        }
    }

    private func pollTimeline(force: Bool) async {
        guard let token = tokenProvider(), let id = selectedID else { return }
        let key = timelineKey()
        guard force || key != lastTimelineKey else { return }
        lastTimelineKey = key
        do {
            let response = try await client.timeline(token: token, session: id)
            if selectedID == id { events = response.events }
        } catch {
            if selectedID == id, events.isEmpty { events = [] }
        }
    }

    /// 只有选中会话的内容变了才重新拉时间线（updatedAt + 子会话运行态）。
    private func timelineKey() -> String {
        guard let root = selectedRoot else { return "" }
        let children = root.children.map { "\($0.id):\(Int($0.updatedAt)):\($0.running)" }.joined(separator: ",")
        return "\(root.id):\(Int(root.updatedAt)):\(root.running):\(children)"
    }

    private func startMetricsPoll() {
        guard !metricsInFlight else { return }
        metricsInFlight = true
        Task { [weak self] in
            await self?.pollMetrics()
            self?.metricsInFlight = false
        }
    }

    private func pollMetrics() async {
        guard tokenProvider() != nil else { return }
        let engine = metricsEngine
        let wantLimits = limits == nil
        let sample = await Task.detached(priority: .utility) { () -> (ContainerMetrics?, ContainerLimits?) in
            _ = engine.selectTransport()
            return (engine.stats(), wantLimits ? engine.limits() : nil)
        }.value
        if let metrics = sample.0 { self.metrics = metrics }
        if let fetched = sample.1 { limits = fetched }
    }

    private func recountArtifacts() {
        guard let id = selectedID, let root = AppPaths.projectRoot else { artifactCount = 0; return }
        let directory = URL(fileURLWithPath: root).appendingPathComponent("dsh-home/artifacts/\(id)")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        artifactCount = files.count
    }

    // MARK: - 选中

    func select(_ id: String?, syncWeb: Bool) {
        guard selectedID != id else { return }
        selectedID = id
        events = []
        lastTimelineKey = ""
        artifactCount = 0
        if let id, !roots.contains(where: { $0.id == id }) {
            pendingSelection = (id, Date().addingTimeInterval(45))
        } else {
            pendingSelection = nil
        }
        guard let id else { return }
        if syncWeb { onSelectInWeb?(id) }
        Task {
            await pollTimeline(force: true)
            recountArtifacts()
        }
    }

    // MARK: - 动作

    func newTask() async {
        guard let token = tokenProvider() else { return }
        do {
            let id = try await client.createSession(token: token)
            await pollSessions()
            select(id, syncWeb: true)
            note(Copy.noteTaskCreated)
        } catch {
            note(error.localizedDescription)
        }
    }

    func stopCurrentTask() async {
        guard let token = tokenProvider() else { return }
        let target = selectedRoot?.running == true ? selectedID : runningRoots.first?.id
        guard let id = target else { note(Copy.noteNothingRunning); return }
        do {
            try await client.cancel(token: token, session: id)
            note(Copy.noteStopRequested)
        } catch RelayError.http(let code, let message) {
            // 上游对「不在运行的会话」返回 502 not found：语义上等价于已经停了。
            note(code == 502 ? Copy.noteAlreadyStopped : message)
        } catch {
            note(error.localizedDescription)
        }
        await pollSessions()
    }

    func openArtifactsFolder() {
        guard let root = AppPaths.projectRoot, let id = selectedID else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("dsh-home/artifacts/\(id)")
        NSWorkspace.shared.open(url)
    }

    private func note(_ message: String) {
        actionNote = message
        noteToken &+= 1
        let mine = noteToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, self.noteToken == mine else { return }
            self.actionNote = nil
        }
    }
}
