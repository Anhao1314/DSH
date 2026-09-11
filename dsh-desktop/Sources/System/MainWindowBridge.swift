import SwiftUI
import AppKit

/// 把 SwiftUI 窗口交给 AppDelegate 接管（关窗=隐藏、禁用状态恢复、只认一扇主窗）。
///
/// 用 `NSViewRepresentable` 而不是遍历 `NSApp.windows`：窗口在 `makeNSView` 时可能还没
/// 挂到 window 上，所以在 `make` 与 `update` 两处都尝试一次，交接本身幂等。
struct MainWindowBridge: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        handOff(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        handOff(from: nsView)
    }

    private func handOff(from view: NSView) {
        // 用 Task(@MainActor) 而不是 DispatchQueue.main.async：既保证在主线程交接，
        // 又让编译期知道闭包落在 MainActor 上（窗口在 make 时还未必挂到 NSWindow）。
        Task { @MainActor [weak view] in
            guard let window = view?.window else { return }
            onWindow(window)
        }
    }
}
