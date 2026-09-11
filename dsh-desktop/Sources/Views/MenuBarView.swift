import SwiftUI

/// 菜单栏驻留菜单（规格 §3.3）。
///
/// 图标随状态切换（停止中/空闲/容器不可用），菜单项固定六项：
/// 显示主窗口 ── 当前任务与状态 / 停止当前任务 / 重启容器 ── 停止容器并退出。
struct MenuBarView: View {
    @EnvironmentObject private var stack: StackController
    @EnvironmentObject private var store: AppStore
    @ObservedObject var app: AppDelegate

    var body: some View {
        Button(Copy.menuShowWindow) { app.showMainWindow() }

        Divider()

        Text(app.isWaitingToQuit ? Copy.menuWaitingQuit : taskLine)

        Button(Copy.actionStopTask) {
            Task { await store.stopCurrentTask() }
        }
        .disabled(!store.isAnyRunning)

        Button(Copy.actionRestartContainer) { stack.restartContainer() }

        Divider()

        Button(Copy.menuStopAndQuit) { app.quitStoppingContainer() }
    }

    private var taskLine: String {
        guard let root = store.runningRoots.first ?? store.selectedRoot else { return Copy.menuNoTask }
        let status = root.running ? Copy.inspectorRunning : Copy.inspectorIdle
        return "\(Notifier.truncated(root.title)) · \(status)"
    }
}
