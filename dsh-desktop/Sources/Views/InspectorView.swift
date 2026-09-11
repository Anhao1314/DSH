import SwiftUI

/// 右栏：团队 / 故事线 / 容器 / 产物。非 Web 区域，全部走系统材质与系统色。
struct InspectorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if case .offline(let detail) = store.relayPhase {
                    offlineCard(detail)
                }
                teamCard
                timelineCard
                containerCard
                artifactsCard
            }
            .padding(8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 离线

    private func offlineCard(_ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.inspectorOfflineTitle).font(.caption.weight(.semibold))
                Text(Copy.inspectorOfflineHint).font(.caption2).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.orange.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 团队

    private var teamCard: some View {
        SectionCard(title: Copy.inspectorTeam, systemImage: "person.2") {
            if let root = store.selectedRoot {
                leadRow(root)
                ForEach(root.children) { child in
                    childRow(child)
                }
                if root.children.isEmpty {
                    HintRow(systemImage: "ellipsis.circle", text: Copy.inspectorTimelineEmpty)
                }
            } else {
                HintRow(systemImage: "questionmark.circle", text: Copy.inspectorNoTask)
            }
        }
    }

    private func leadRow(_ root: SessionRoot) -> some View {
        HStack(spacing: 8) {
            StatusDot(running: root.running, verdict: root.verdict)
            Text(Copy.roleLead).font(.callout)
            Text("\(root.turns) 轮").font(.caption2).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text(root.running ? Copy.inspectorRunning : (root.verdict.isEmpty ? Copy.inspectorDone : root.statusText))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lead，\(root.statusText)")
    }

    private func childRow(_ child: SessionChild) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)
            Circle().fill(roleColor(child.role)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(child.label.isEmpty ? RoleDisplay.text(child.role) : child.label)
                    .font(.caption)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(RoleDisplay.text(child.role))
                    if child.settledMs > 0 {
                        Text("·")
                        Text(Format.duration(child.settledMs)).monospacedDigit()
                    }
                    if child.running {
                        Text("·")
                        Text(Copy.inspectorRunning)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VerdictIcon(verdict: child.verdict).font(.caption)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RoleDisplay.text(child.role))，\(child.label)，\(SessionStatus.text(running: child.running, verdict: child.verdict))")
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "coder": return .green
        case "reviewer": return .orange
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    // MARK: - 故事线

    private var timelineCard: some View {
        SectionCard(title: Copy.inspectorTimeline, systemImage: "text.bubble") {
            if store.events.isEmpty {
                HintRow(systemImage: "clock", text: Copy.inspectorTimelineEmpty)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.events) { event in
                        TimelineRow(event: event)
                    }
                }
            }
        }
    }

    // MARK: - 容器

    private var containerCard: some View {
        SectionCard(title: Copy.inspectorContainer, systemImage: "cpu") {
            if let metrics = store.metrics {
                VStack(alignment: .leading, spacing: 8) {
                    MetricRow(
                        title: "CPU",
                        valueText: Format.percent(metrics.cpuPercent),
                        fraction: metrics.cpuPercent / 100,
                        tint: .accentColor
                    )
                    MetricRow(
                        title: "内存",
                        valueText: "\(Format.gb(metrics.memoryBytes))/\(Format.gb(metrics.memoryLimitBytes))",
                        fraction: metrics.memoryFraction,
                        tint: .teal
                    )
                    Text(limitLine).font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                HintRow(systemImage: "cpu", text: Copy.inspectorMetricsUnavailable)
            }
        }
    }

    private var limitLine: String {
        guard let limits = store.limits, limits.cpus > 0 || limits.memoryBytes > 0 else { return Copy.inspectorCoresFallback }
        let cores = limits.cpus > 0 ? String(format: "%.0f 核", limits.cpus) : "—"
        let memory = limits.memoryBytes > 0 ? Format.gb(limits.memoryBytes) : "—"
        return "\(Copy.inspectorCoresPrefix) · 上限 \(cores) / \(memory)"
    }

    // MARK: - 产物

    private var artifactsCard: some View {
        SectionCard(title: Copy.inspectorArtifacts, systemImage: "folder", subtitle: "\(store.artifactCount)") {
            if store.selectedID == nil {
                HintRow(systemImage: "folder", text: Copy.inspectorNoTask)
            } else if store.artifactCount == 0 {
                HintRow(systemImage: "folder", text: Copy.inspectorArtifactsEmpty)
            } else {
                HStack {
                    Text("\(store.artifactCount) 个文件").font(.caption)
                    Spacer()
                    Button(Copy.actionOpenArtifacts) { store.openArtifactsFolder() }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// 故事线单行：图标 + 标题 + 次要说明（超长可展开）。
private struct TimelineRow: View {
    let event: TimelineEvent
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? event.kind : event.title)
                    .font(.caption)
                    .lineLimit(2)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if event.detail.count > 120 {
                        Button(expanded ? Copy.inspectorCollapse : Copy.inspectorExpand) {
                            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.detail.isEmpty ? event.title : "\(event.title)。\(event.detail)")
    }

    private var icon: String {
        switch event.kind {
        case "turn": return "arrow.down.circle"
        case "delegate": return event.status == "done" ? "checkmark.circle.fill" : "person.2"
        case "verdict": return event.status == "pass" ? "checkmark.seal.fill" : "xmark.octagon.fill"
        case "plan": return "list.bullet.rectangle"
        case "todo": return "checklist"
        default: return "circle"
        }
    }

    private var iconColor: Color {
        switch (event.kind, event.status) {
        case ("verdict", "pass"): return .green
        case ("verdict", "fail"): return .orange
        case ("delegate", "done"): return .green
        default: return Color(nsColor: .secondaryLabelColor)
        }
    }
}
