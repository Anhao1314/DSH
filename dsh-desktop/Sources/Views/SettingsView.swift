import SwiftUI
import AppKit

/// 设置（规格 §3.5）：只有四组信息，**不出现**生命周期策略类开关。
struct SettingsView: View {
    @EnvironmentObject private var stack: StackController
    @EnvironmentObject private var store: AppStore
    @ObservedObject var app: AppDelegate

    @AppStorage(Notifier.preferenceKey) private var notificationsEnabled = true
    @State private var note: String?

    private let engine = DockerEngine()

    var body: some View {
        Form {
            Section(Copy.settingsProject) {
                LabeledContent(Copy.settingsProjectPath) {
                    Text(ProjectLocator.shared.cachedRoot?.path ?? Copy.settingsUnknown)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Button(Copy.settingsReveal) { revealProject() }
                        .disabled(ProjectLocator.shared.cachedRoot == nil)
                    Button(Copy.settingsChangeProject) { changeProject() }
                }
            }

            Section(Copy.settingsNotifications) {
                Toggle(Copy.settingsNotifyToggle, isOn: $notificationsEnabled)
                Text(Copy.settingsNotifyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Copy.settingsResources) {
                LabeledContent(Copy.settingsCpuLimit) {
                    Text(limitsCores).monospacedDigit()
                }
                LabeledContent(Copy.settingsMemoryLimit) {
                    Text(limitsMemory).monospacedDigit()
                }
                LabeledContent(Copy.settingsUsage) {
                    Text(usage).monospacedDigit()
                }
                Text(Copy.settingsResourcesHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Copy.settingsDiagnostics) {
                LabeledContent(Copy.settingsVersion) {
                    Text(Self.versionText).monospacedDigit()
                }
                HStack(spacing: 8) {
                    Button(Copy.settingsOpenHome) { openHome() }
                        .disabled(ProjectLocator.shared.cachedRoot == nil)
                    Button(Copy.settingsExportLogs) { exportLogs() }
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .padding(.vertical, 6)
    }

    // MARK: - 取值

    private var limitsCores: String {
        guard let limits = store.limits else { return Copy.settingsUnknown }
        return Copy.settingsCoresValue(limits.cpus)
    }

    private var limitsMemory: String {
        guard let limits = store.limits else { return Copy.settingsUnknown }
        return Format.gb(limits.memoryBytes)
    }

    private var usage: String {
        guard let metrics = store.metrics else { return Copy.settingsUnknown }
        return "\(Format.percent(metrics.cpuPercent)) · \(Format.gb(metrics.memoryBytes))"
    }

    static var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - 动作

    private func revealProject() {
        guard let root = ProjectLocator.shared.cachedRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func changeProject() {
        if let message = ProjectChooser.choose() {
            note = message
        } else {
            note = Copy.settingsProjectChanged
            stack.start()
        }
    }

    private func openHome() {
        guard let root = ProjectLocator.shared.cachedRoot else { return }
        NSWorkspace.shared.open(root.appendingPathComponent("dsh-home", isDirectory: true))
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dsh-logs.txt"
        panel.canCreateDirectories = true
        panel.message = Copy.settingsExportLogs
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = engine.selectTransport()
        let text = LogRedaction.redact(engine.logsTail(lines: 200))
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            note = Copy.settingsExportDone
        } catch {
            note = Copy.settingsExportFailed
        }
    }
}
