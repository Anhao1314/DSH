import SwiftUI
import AppKit

/// 启动屏（ready 前唯一界面）与失败面板（图标 + 说明 + 主动作 + 可展开日志）。
struct BootView: View {
    @EnvironmentObject private var stack: StackController
    var onChooseProject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(headline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if case .failed(let error) = stack.phase {
                failure(error)
            } else {
                ProgressView().controlSize(.small)
                Text(stack.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !stack.transportLine.isEmpty, case .failed = stack.phase {
                Text("Docker 通道：\(stack.transportLine)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .frame(maxWidth: 460)
    }

    @ViewBuilder private func failure(_ error: StackError) -> some View {
        Text(error.message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        Button(error.primaryActionTitle) {
            switch error.primaryAction {
            case .retry: stack.start()
            case .downloadOrbStack: StackController.openOrbStackDownload()
            case .chooseProject: onChooseProject()
            }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)

        DisclosureGroup(Copy.logSectionTitle) {
            ScrollView {
                Text(stack.logTail.isEmpty ? Copy.logEmpty : stack.logTail)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 160)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .font(.callout)
        .frame(maxWidth: 420)
    }

    private var iconName: String {
        if case .failed(let error) = stack.phase { return error.icon }
        return "shippingbox"
    }

    private var iconColor: Color {
        if case .failed = stack.phase { return .orange }
        return .accentColor
    }

    private var headline: String {
        if case .failed(let error) = stack.phase { return error.title }
        return Copy.bootTitle
    }
}
