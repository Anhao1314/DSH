import Foundation

/// 全部界面文案（简体中文）集中在这里，改文案只改这一处。
enum Copy {
    // 品牌
    static let appName = "DSH 团队工作台"
    static let windowTitle = "DSH 团队工作台"

    // 启动屏
    static let bootTitle = "正在准备团队工作台"
    static let bootSubtitle = "本地容器 + 原生壳，全部数据不出这台 Mac。"
    static let phaseCheckingOrb = "检查 OrbStack…"
    static let phaseStartingOrb = "启动 OrbStack…"
    static let phaseComposeUp = "启动容器…"
    static let phaseWaitingHealth = "等待就绪…"
    static let phaseReadingToken = "读取凭据…"
    static let phaseConnecting = "连接中继…"
    static let phaseReady = "就绪"
    static let phaseIdle = "准备中…"

    // 通用按钮
    static let actionRetry = "重试"
    static let actionRestartContainer = "重启容器"
    static let actionStopContainer = "停止容器"
    static let actionReload = "重新载入页面"
    static let actionOpenInBrowser = "在浏览器打开"
    static let actionOpenLogs = "查看日志"
    static let actionDownloadOrbStack = "下载 OrbStack"
    static let actionChooseProject = "选择项目目录"

    // 错误
    static let projectMissingTitle = "找不到 dsh-workbench 工程"
    static let projectMissingMessage = "请选择包含 orbstack/compose.yaml 与 deepseek-harness/orbstack-relay.cjs 的 dsh-workbench 文件夹。"
    static let orbNotFoundTitle = "没有找到 OrbStack"
    static let orbNotFoundMessage = "DSH 的容器跑在 OrbStack 上。安装并打开 OrbStack 后点重试即可。"
    static let orbStartTimeoutTitle = "OrbStack 没有就绪"
    static let orbStartTimeoutMessage = "已尝试启动 OrbStack，但 60 秒内没能连上 Docker。请手动打开 OrbStack 后重试。"
    static let composeFailedTitle = "容器启动失败"
    static let healthTimeoutTitle = "容器没有变成 healthy"
    static let healthTimeoutMessage = "容器可能仍在启动或已崩溃，展开日志可以看到最后一屏输出。"
    static let tokenMissingTitle = "读不到登录凭据"
    static let tokenMissingMessage = "容器已就绪但日志里没有 token，重启容器通常可以恢复。"
    static let relayUnreachableTitle = "中继没有响应"
    static let relayUnreachableMessage = "无法连到本机 3081 端口的中继。容器可能已停止，点重试重新拉起。"
    static let socketFailedTitle = "Docker 通道不可用"

    // 侧边栏 / 状态
    static let sidebarRecent = "最近"
    static let sidebarOlder = "更早"
    static let sidebarRunning = "进行中"
    static let sidebarPassed = "已通过"
    static let sidebarFailed = "有问题"
    static let sidebarDone = "完成"
    static let sidebarSyncing = "正在同步任务列表"
    static let sidebarNewTask = "新任务"
    static let sidebarWaitingFirstTurn = "等待下发第一条指令"
    static let sidebarEmptyTitle = "还没有任务"
    static let sidebarEmptyHint = "点工具栏的「新任务」开始"
    static let roleSub = "子任务"
    static let roleLead = "Lead"

    // 工具栏
    static let actionNewTask = "新任务"
    static let actionStopTask = "停止任务"
    static let helpStopTask = "只中止当前轮次，容器继续运行"
    static let actionOpenArtifacts = "在 Finder 打开"

    // Inspector
    static let inspectorTeam = "团队"
    static let inspectorTimeline = "故事线"
    static let inspectorContainer = "容器"
    static let inspectorArtifacts = "产物"
    static let inspectorNoTask = "未选择任务"
    static let inspectorTimelineEmpty = "Lead 尚未委派，等待中…"
    static let inspectorArtifactsEmpty = "本次任务还没有产物"
    static let inspectorCoresPrefix = "OrbStack"
    static let inspectorCoresFallback = "OrbStack・读取容器上限…"
    static let inspectorMetricsUnavailable = "读不到容器指标"
    static let inspectorRunning = "运行中"
    static let inspectorIdle = "空闲"
    static let inspectorDone = "已完成"
    static let inspectorExpand = "展开"
    static let inspectorCollapse = "收起"
    static let inspectorOfflineTitle = "离线"
    static let inspectorOfflineHint = "与中继的连接中断，正在自动重试…"

    // 动作反馈
    static let noteTaskCreated = "已新建任务"
    static let noteStopRequested = "已请求停止当前轮次"
    static let noteAlreadyStopped = "该任务已不在运行"
    static let noteNothingRunning = "当前没有运行中的任务"

    // 日志
    static let logSectionTitle = "查看日志"
    static let logEmpty = "（暂无容器日志）"
}
