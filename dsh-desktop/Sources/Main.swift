import SwiftUI
import AppKit

@main
struct DSHTeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stack = StackController()
    @StateObject private var store = AppStore()
    @StateObject private var webStore = WebViewStore()

    var body: some Scene {
        WindowGroup(Copy.windowTitle) {
            RootSplitView()
                .environmentObject(stack)
                .environmentObject(store)
                .environmentObject(webStore)
                .frame(minWidth: 1000, minHeight: 640)
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
    }

    private var isReady: Bool {
        if case .ready = stack.phase { return true }
        return false
    }

    /// 三块状态对象的接线：轮询数据取自中继，切会话走 JS 桥，页面事件回流到 store。
    private func wire() {
        store.setTokenProvider { KeychainStore.readToken() }
        store.onSelectInWeb = { sessionID in
            webStore.select(session: sessionID)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Policy A：退出应用时停掉 dsh 容器，让本机占用归零。
    func applicationWillTerminate(_ notification: Notification) {
        StackController.stopOnQuit()
    }
}
