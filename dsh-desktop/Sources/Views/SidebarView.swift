import SwiftUI

/// 左栏：最近任务列表（运行中脉冲点 / 结论色 / HH:mm），更早分组可折叠。
struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var olderExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if store.roots.isEmpty {
                emptyState
            } else {
                List {
                    Section(Copy.sidebarRecent) {
                        if let pendingID = store.pendingNewTaskID {
                            pendingRow(pendingID)
                        }
                        ForEach(store.recentRoots) { root in
                            row(root)
                        }
                    }
                    if !store.olderRoots.isEmpty {
                        Section {
                            if olderExpanded {
                                ForEach(store.olderRoots) { root in
                                    row(root)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { olderExpanded.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: olderExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(Copy.sidebarOlder) · \(store.olderRoots.count)")
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            if store.sessionsStale, let last = store.lastSessionsAt {
                Divider()
                HintRow(systemImage: "arrow.clockwise", text: "\(Copy.sidebarSyncing) · \(Format.hhmm(last.timeIntervalSince1970 * 1000))")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            if let note = store.actionNote {
                Divider()
                HintRow(systemImage: "info.circle", text: note)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
    }

    /// 新建但还没跑出首轮的任务：临时占位行（一旦有了投影就换成真实行）。
    private func pendingRow(_ id: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(running: true, verdict: "")
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.sidebarNewTask).font(.system(size: 12.5, weight: .semibold))
                Text(Copy.sidebarWaitingFirstTurn).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Copy.sidebarNewTask)，\(Copy.sidebarWaitingFirstTurn)")
    }

    private func row(_ root: SessionRoot) -> some View {
        let selected = root.id == store.selectedID
        return HStack(alignment: .top, spacing: 8) {
            StatusDot(running: root.running, verdict: root.verdict)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(root.title.isEmpty ? Copy.inspectorNoTask : root.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(root.statusText)
                    Text("·")
                    Text(Format.hhmm(root.updatedAt)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VerdictIcon(verdict: root.verdict)
                .font(.caption)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { store.select(root.id, syncWeb: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(root.title)，\(root.statusText)，\(Format.hhmm(root.updatedAt))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray.full").font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(Copy.sidebarEmptyTitle).font(.callout.weight(.medium))
            Text(Copy.sidebarEmptyHint).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}
