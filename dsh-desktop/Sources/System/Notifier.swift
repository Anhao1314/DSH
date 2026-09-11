import Foundation
import AppKit
import UserNotifications

/// 完成 / 异常通知（规格 §3.4）。
///
/// * 首次有任务运行时请求授权；设置里可以整体关掉（默认开）。
/// * 窗口可见时不打扰（不投递）。
/// * `UNUserNotificationCenter` 对 ad-hoc 签名的本地 App 可能拒绝投递：这里所有调用
///   都是「失败即降级」，绝不因此崩溃或阻塞主流程。
final class Notifier {
    static let shared = Notifier()

    /// 设置里的开关（默认开）。
    static let preferenceKey = "notifications.enabled"

    static var preferenceEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: preferenceKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: preferenceKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: preferenceKey) }
    }

    private let center = UNUserNotificationCenter.current()
    private var requestedAuthorization = false

    private init() {}

    /// 首个任务开始运行时调用一次即可（重复调用无副作用）。
    func requestAuthorizationIfNeeded() {
        guard Notifier.preferenceEnabled, !requestedAuthorization else { return }
        requestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 任务结束：标题 = 会话标题截断 30 字，正文由调用方按角色给结论。
    func taskFinished(title: String, body: String) {
        post(title: title, body: body)
    }

    func containerUnhealthy() {
        post(title: Copy.notifyContainerTitle, body: Copy.notifyContainerBody)
    }

    private func post(title: String, body: String) {
        guard Notifier.preferenceEnabled, !Notifier.isUserWatching else { return }
        let content = UNMutableNotificationContent()
        content.title = Notifier.truncated(title)
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    /// 「窗口可见」= App 在前台且至少有一扇可见的非最小化窗口。
    static var isUserWatching: Bool {
        guard NSApp.isActive else { return false }
        return NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
    }

    static func truncated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else { return trimmed.isEmpty ? Copy.appName : trimmed }
        return String(trimmed.prefix(30)) + "…"
    }
}
