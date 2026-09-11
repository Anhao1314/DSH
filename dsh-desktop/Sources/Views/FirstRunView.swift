import SwiftUI
import AppKit

/// 首启向导（规格 §3.5）：定位不到合法工程目录时全屏替代主界面。
struct FirstRunView: View {
    @EnvironmentObject private var stack: StackController
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(Copy.firstRunTitle)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                bullet(Copy.firstRunLine1)
                bullet(Copy.firstRunLine2)
                bullet(Copy.firstRunLine3)
            }
            .frame(maxWidth: 460, alignment: .leading)

            Button(Copy.firstRunChoose) { choose() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(Copy.firstRunInvalidPrefix)：\(errorText)")
            }

            Text(ProjectLocator.shared.lastSearchNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func choose() {
        errorText = ProjectChooser.choose()
        if errorText == nil { stack.start() }
    }
}

/// 选目录 + 校验 + 落盘。返回 nil 表示「已选中」或「用户取消」；返回文案表示内联错误。
enum ProjectChooser {
    static func choose(startAt current: URL? = ProjectLocator.shared.cachedRoot) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = Copy.projectMissingMessage
        panel.prompt = Copy.actionChooseProject
        panel.directoryURL = current?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard ProjectLocator.shared.validate(url) else { return Copy.firstRunInvalid }
        do {
            try ProjectLocator.shared.save(url)
            return nil
        } catch {
            return Copy.firstRunSaveFailed
        }
    }
}
