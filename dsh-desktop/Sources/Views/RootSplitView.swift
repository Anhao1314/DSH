import SwiftUI
import AppKit

/// 三栏主界面：左会话列表 220 / 中 WKWebView（唯一允许 Web 内容的地方）/ 右 Inspector 300。
/// 启动未就绪时整屏交给启动屏（BootView）。
struct RootSplitView: View {
    @EnvironmentObject private var stack: StackController
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var webStore: WebViewStore

    var body: some View {
        if needsFirstRun {
            FirstRunView()
        } else {
            mainSplit
        }
    }

    /// 定位不到合法工程目录：整屏交给首启向导（§3.5）。
    private var needsFirstRun: Bool {
        if case .failed(.projectMissing) = stack.phase { return true }
        return false
    }

    private var mainSplit: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } content: {
            consolePane
                .navigationSplitViewColumnWidth(min: 420, ideal: 720)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
    }

    private var isReady: Bool {
        if case .ready = stack.phase { return true }
        return false
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.newTask() }
            } label: {
                Label(Copy.actionNewTask, systemImage: "plus")
            }
            .help(Copy.actionNewTask)
            .disabled(!isReady)

            Button {
                Task { await store.stopCurrentTask() }
            } label: {
                Label(Copy.actionStopTask, systemImage: "stop.circle")
            }
            .help(Copy.helpStopTask)
            .disabled(!store.isAnyRunning)

            Button {
                stack.restartContainer()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help(Copy.actionRestartContainer)

            Button {
                webStore.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(Copy.actionReload)

            Button {
                if let url = stack.consoleURL { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "safari")
            }
            .help(Copy.actionOpenInBrowser)
            .disabled(stack.consoleURL == nil)
        }
    }

    @ViewBuilder private var consolePane: some View {
        ZStack {
            // 只把「基础 URL（含 token）」交给 WebView；切会话一律走 JS 桥，
            // 不在这里拼 ?session=（否则每次选中都会整页重载，违反 M3 验收③）。
            if case .ready = stack.phase, let url = stack.consoleURL {
                WebView(url: url, store: webStore, onFail: {
                    if case .ready = stack.phase { stack.start() }
                })
                if case .offline = store.relayPhase {
                    VStack {
                        offlineBanner
                        Spacer()
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            } else {
                BootView(onChooseProject: { ChooseProjectPanel.present(stack: stack) })
            }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
            Text(Copy.inspectorOfflineHint).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// 首启向导也用它（M4 会换成全屏向导）；这里先集中一处，避免两套逻辑。
enum ChooseProjectPanel {
    static func present(stack: StackController) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = Copy.projectMissingMessage
        panel.prompt = Copy.actionChooseProject
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if ProjectLocator.shared.validate(url) {
            try? ProjectLocator.shared.save(url)
            stack.start()
        } else {
            let alert = NSAlert()
            alert.messageText = Copy.projectMissingTitle
            alert.informativeText = Copy.projectMissingMessage
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
