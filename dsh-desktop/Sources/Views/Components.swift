import SwiftUI

/// 运行状态点：运行中做 0.2s easeInOut 的呼吸（opacity 往返），其余为静态语义色。
/// 颜色只是辅助：无障碍标签里同样带状态文字（红线：状态不能只靠颜色表达）。
struct StatusDot: View {
    let running: Bool
    let verdict: String
    var size: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(running && pulsing ? 0.3 : 1)
            .onAppear { sync() }
            .onChange(of: running) { _ in sync() }
    }

    private var color: Color {
        if running { return .accentColor }
        switch verdict {
        case "pass": return .green
        case "fail": return .orange
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private func sync() {
        if running {
            withAnimation(.easeInOut(duration: 0.2).repeatForever(autoreverses: true)) { pulsing = true }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { pulsing = false }
        }
    }
}

/// 结论图标：pass = checkmark.seal.fill（绿）、fail = xmark.octagon.fill（橙）。
struct VerdictIcon: View {
    let verdict: String
    var body: some View {
        switch verdict {
        case "pass":
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).accessibilityLabel(Copy.sidebarPassed)
        case "fail":
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.orange).accessibilityLabel(Copy.sidebarFailed)
        default:
            EmptyView().accessibilityHidden(true)
        }
    }
}

/// 资源条：0.5px 描边 + 系统材质的卡片，内部 8pt 间距。
struct MetricRow: View {
    let title: String
    let valueText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("\(title) \(valueText)")
        }
    }
}

/// Inspector 的可折叠卡片（默认展开，标题即展开/收起按钮）。
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: systemImage).font(.caption).foregroundStyle(.secondary)
                    Text(title).font(.subheadline.weight(.semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "已展开" : "已收起")

            if expanded { content() }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

/// 统一的次要说明行（空态 / 离线提示）。
struct HintRow: View {
    let systemImage: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage).font(.caption2).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

enum Format {
    static func hhmm(_ milliseconds: Double) -> String {
        guard milliseconds > 0 else { return "--:--" }
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return String(format: value >= 1 ? "%.2fG" : "%.0fM", value >= 1 ? value : value * 1024)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value, 0), 999))
    }

    static func duration(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "" }
        let seconds = max(1, Int((Double(milliseconds) / 1000).rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return "\(minutes)m\(seconds % 60)s"
    }
}
