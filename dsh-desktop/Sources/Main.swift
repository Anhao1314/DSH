import SwiftUI
import AppKit

@main
struct DSHTeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stack = StackController()
    @StateObject private var store = AppStore()
    @StateObject private var webStore = WebViewStore()

    var body: some Scene {
        // `Window`（不是 WindowGroup）：工作台只有一扇主窗，点 Dock / 菜单只把它叫回来。
        Window(Copy.windowTitle, id: Self.mainWindowID) {
            RootSplitView()
                .environmentObject(stack)
                .environmentObject(store)
                .environmentObject(webStore)
                .frame(minWidth: 1000, minHeight: 640)
                .background(MainWindowBridge { appDelegate.adopt($0) })
                .onAppear(perform: wire)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button(Copy.actionNewTask) { Task { await store.newTask() } }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!isReady)
            }
            CommandGroup(after: .sidebar) {
                Button(Copy.actionStopTask) { Task { await store.stopCurrentTask() } }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!store.isAnyRunning)
                Divider()
                Button(Copy.actionReload) { webStore.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(Copy.actionRestartContainer) { stack.restartContainer() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(app: appDelegate)
                .environmentObject(stack)
                .environmentObject(store)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(app: appDelegate)
                .environmentObject(stack)
                .environmentObject(store)
        }
    }

    static let mainWindowID = "workbench-main"

    /// 图标随状态：跑任务 = stop.circle.fill；空闲 = shippingbox；容器不可用 = 警告。
    /// 注意：菜单栏必须是真实存在的 SF Symbol —— `cube.container` 在本机不存在（渲染为空白），
    /// 已核对过的替代品是 `shippingbox`（见 NOTES-api.md 第 0 节符号核验）。
    private var menuBarIcon: String {
        if case .failed = stack.phase { return "exclamationmark.triangle" }
        if case .ready = stack.phase { return store.isAnyRunning ? "stop.circle.fill" : "shippingbox" }
        return "shippingbox"
    }

    private var isReady: Bool {
        if case .ready = stack.phase { return true }
        return false
    }

    /// 三块状态对象的接线：轮询数据取自中继，切会话走 JS 桥，页面事件回流到 store。
    private func wire() {
        let delegate = appDelegate
        delegate.store = store
        delegate.stack = stack
        store.setTokenProvider { KeychainStore.readToken() }
        store.onSelectInWeb = { sessionID in
            webStore.select(session: sessionID)
        }
        store.onRunningStateChanged = { running in
            delegate.taskRunningStateChanged(running)
        }
        store.onTokenStale = { [weak stack] in
            stack?.refreshToken()
        }
        store.onContainerUnhealthy = {
            Notifier.shared.containerUnhealthy()
        }
        webStore.onHostEvent = { event in
            switch event.kind {
            case .selectionChanged:
                store.select(event.sessionId, syncWeb: false)
            case .runningChanged, .taskFinished:
                Task { await store.refresh() }
            }
        }
        stack.start()
        store.start()
    }
}

/// 窗口与退出的唯一负责人：关窗=隐藏、⌘Q 三分支、退出时 Policy A 停容器。
/// AppKit 的 delegate 回调都在主线程，这里整体声明为 MainActor，避免与 AppStore 的数据竞争。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    /// 正在等任务跑完再退出（菜单栏显示进度）。
    @Published private(set) var isWaitingToQuit = false

    weak var store: AppStore?
    weak var stack: StackController?

    private weak var mainWindow: NSWindow?
    private var forceQuit = false

    // MARK: - 窗口

    /// SwiftUI 窗口挂上来时接管：成为 delegate、禁用系统状态恢复（多窗口来源）。
    func adopt(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.delegate = self
        window.isRestorable = false
        window.tabbingMode = .disallowed
    }

    /// 关窗 = 隐藏：任务与容器继续跑（唯一模型，不提供设置项）。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 关窗 = 隐藏（规格 §3.3）：任务与容器继续跑，菜单栏「显示主窗口」把它叫回来。
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showMainWindow() {
        NSApp.unhide(nil)
        let window = mainWindow ?? NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 退出

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if forceQuit { return .terminateNow }
        guard let store, store.isAnyRunning else { return .terminateNow }
        guard !isWaitingToQuit else { return .terminateLater }

        let alert = NSAlert()
        alert.messageText = Copy.quitRunningTitle
        alert.informativeText = Copy.quitRunningBody
        alert.alertStyle = .informational
        alert.addButton(withTitle: Copy.quitWait)
        alert.addButton(withTitle: Copy.quitNow)
        alert.addButton(withTitle: Copy.quitCancel)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            isWaitingToQuit = true
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    /// AppStore 汇报「有没有任务在跑」的状态变化。
    func taskRunningStateChanged(_ running: Bool) {
        guard isWaitingToQuit, !running else { return }
        isWaitingToQuit = false
        let title = store?.roots.first?.title ?? Copy.appName
        Notifier.shared.taskFinished(title: title, body: Copy.notifyQuitWhenIdle)
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// 菜单里的「停止容器并退出」：跳过三选一，直接走终止（终止时才停容器）。
    func quitStoppingContainer() {
        forceQuit = true
        NSApp.terminate(nil)
    }

    // Policy A：退出应用时停掉 dsh 容器，让本机占用归零。
    func applicationWillTerminate(_ notification: Notification) {
        StackController.stopOnQuit()
    }
}
