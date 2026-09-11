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

    // M4 菜单栏 / 退出 / 设置 / 首启向导
    static let menuShowWindow = "显示主窗口"
    static let menuNoTask = "当前没有任务"
    static let menuStopAndQuit = "停止容器并退出"
    static let menuWaitingQuit = "等任务完成后退出…"

    static let quitRunningTitle = "还有任务在运行"
    static let quitRunningBody = "现在退出会停掉容器并中止正在跑的任务。也可以等它跑完再自动退出。"
    static let quitWait = "等任务完成后退出"
    static let quitNow = "立即退出（任务与容器将停止）"
    static let quitCancel = "取消"

    static let notifyVerdictPass = "Reviewer 判定：通过"
    static let notifyVerdictFail = "Reviewer 判定：发现问题"
    static let notifyTaskDone = "任务已完成"
    static let notifyTeamDone = "Coder 与 Reviewer 已完成"
    static let notifyContainerTitle = "容器不健康"
    static let notifyContainerBody = "dsh 容器没有响应，工作台会在恢复后自动继续。"
    static let notifyQuitWhenIdle = "任务已完成，正在退出…"

    static let relayTokenStale = "登录凭据可能已轮换，正在重读…"

    static let settingsProject = "项目位置"
    static let settingsProjectPath = "工程目录"
    static let settingsReveal = "在 Finder 中显示"
    static let settingsChangeProject = "重新选择"
    static let settingsUnknown = "—"
    static let settingsProjectChanged = "已切换工程目录，正在重新启动…"

    static let settingsNotifications = "通知"
    static let settingsNotifyToggle = "任务结束与容器异常时通知我"
    static let settingsNotifyHint = "窗口在前台可见时不打扰；首次运行任务时系统会询问一次权限。"

    static let settingsResources = "容器资源"
    static let settingsCpuLimit = "CPU 上限"
    static let settingsMemoryLimit = "内存上限"
    static let settingsUsage = "当前占用"
    static let settingsResourcesHint = "上限来自 orbstack/compose.yaml（只读）。要改请编辑该文件后重启容器。"
    static func settingsCoresValue(_ cores: Double) -> String {
        let value = cores > 0 ? cores : 0
        return String(format: value == value.rounded() ? "%.0f 核" : "%.1f 核", value)
    }

    static let settingsDiagnostics = "诊断"
    static let settingsVersion = "版本"
    static let settingsOpenHome = "打开 dsh-home"
    static let settingsExportLogs = "导出最近日志"
    static let settingsExportDone = "日志已导出（已过滤 token）"
    static let settingsExportFailed = "日志导出失败"

    static let firstRunTitle = "先找到你的 dsh-workbench 工程"
    static let firstRunLine1 = "工作台本身只是一个原生外壳：容器、预设与自建控制台都在你的 dsh-workbench 目录里。"
    static let firstRunLine2 = "选定目录后，它会自动启动 OrbStack 里的 dsh 容器并连上本机中继（只监听 127.0.0.1）。"
    static let firstRunLine3 = "目录里必须同时存在 orbstack/compose.yaml 与 deepseek-harness/orbstack-relay.cjs。"
    static let firstRunChoose = "选择 dsh-workbench 文件夹"
    static let firstRunInvalid = "这个目录不像 dsh-workbench：缺少 orbstack/compose.yaml 或 deepseek-harness/orbstack-relay.cjs。"
    static let firstRunInvalidPrefix = "目录不合法"
    static let firstRunSaveFailed = "无法写入设置文件（~/Library/Application Support/DSHTeam/config.json）。"
}
