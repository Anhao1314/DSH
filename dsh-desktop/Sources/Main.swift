import SwiftUI
import AppKit

@main
struct DSHTeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stack = StackController()
    @StateObject private var webStore = WebViewStore()

    var body: some Scene {
        WindowGroup(Copy.windowTitle) {
            ContentView()
                .environmentObject(stack)
                .environmentObject(webStore)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { stack.start() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(Copy.actionReload) { webStore.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button(Copy.actionRestartContainer) { stack.restartContainer() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Policy A：退出应用时停掉 dsh 容器，让本机占用归零。
    func applicationWillTerminate(_ notification: Notification) {
        StackController.stopOnQuit()
    }
}

struct ContentView: View {
    @EnvironmentObject private var stack: StackController
    @EnvironmentObject private var webStore: WebViewStore

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            if case .ready = stack.phase, let url = stack.consoleURL {
                WebView(url: url, store: webStore, onFail: {
                    if case .ready = stack.phase {
                        stack.start()
                    }
                })
                .ignoresSafeArea()
            } else {
                BootView(onChooseProject: chooseProject)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if case .ready = stack.phase {
                    Button { webStore.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(Copy.actionReload)

                    Button { stack.restartContainer() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help(Copy.actionRestartContainer)

                    Button { openInBrowser() } label: {
                        Image(systemName: "safari")
                    }
                    .help(Copy.actionOpenInBrowser)
                    .disabled(stack.consoleURL == nil)
                }
            }
        }
    }

    private func openInBrowser() {
        guard let url = stack.consoleURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseProject() {
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
