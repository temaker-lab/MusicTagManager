import MTMCore
import SwiftUI

/// 작업 이력 + 되돌리기 (작업·곡 단위)
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var pendingUndo: UndoRequest?
    /// 사용자가 직접 펼치거나 접은 작업 (없으면 가장 최근 작업만 펼침)
    @State private var expanded: [Int64: Bool] = [:]

    struct UndoRequest: Identifiable {
        let id = UUID()
        let scope: UndoScope
        let description: String
    }

    var body: some View {
        Group {
            if state.jobRows.isEmpty {
                ContentUnavailableView(L("history.empty.title"), systemImage: "clock.arrow.circlepath",
                                       description: Text(L("history.empty.desc")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 작업 단위로 펼친다. 가장 최근 작업만 펼친 채로 시작하고, 지난 작업은 일시·곡 수만 보인다.
                List {
                    ForEach(state.jobRows) { job in
                        DisclosureGroup(isExpanded: expansion(for: job)) {
                            ForEach(job.items) { item in
                                itemRow(item, job: job)
                            }
                        } label: {
                            jobHeader(job)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .task { state.reloadJobs() }
        .confirmationDialog(pendingUndo.map { Lf("history.confirmUndo.title", $0.description) } ?? "",
                            isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }),
                            presenting: pendingUndo) { request in
            Button(L("history.undo"), role: .destructive) {
                Task { await state.undo(request.scope) }
            }
        } message: { _ in
            Text(L("history.confirmUndo.msg"))
        }
    }

    private func expansion(for job: JobRow) -> Binding<Bool> {
        Binding(
            get: { expanded[job.id] ?? (job.id == state.jobRows.first?.id) },
            set: { expanded[job.id] = $0 }
        )
    }

    private func jobHeader(_ job: JobRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: job.isUndo ? "arrow.uturn.backward.circle" : "square.and.pencil")
                .foregroundStyle(.secondary)
            Text(job.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(appLocale))).font(.headline)
            Text(job.title).font(.callout).foregroundStyle(.secondary)
            Text(job.summary).font(.callout).foregroundStyle(.secondary)
            Spacer()
            if !job.isFinished {
                Button(L("history.resume")) { Task { await state.resume(jobID: job.id) } }
                    .disabled(state.isApplying)
                Button(L("history.cancelRemaining")) { state.cancel(jobID: job.id) }
                    .disabled(state.isApplying)
            }
            if job.canUndo {
                Button(L("history.undoWholeJob")) {
                    pendingUndo = UndoRequest(scope: .job(job.id), description: Lf("history.undoDescWholeJob", job.title))
                }
                .disabled(state.isApplying)
            }
        }
    }

    private func itemRow(_ item: JobRow.Item, job: JobRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: icon(item))
                .foregroundStyle(color(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Group {
                    if !item.changedFields.isEmpty { Text(Lf("history.changed", item.changedFields)) }
                    if let message = item.message { Text(message) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.undone ? L("history.undone") : item.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if job.canUndo, item.state.wrote, !item.undone, let id = PersistentID(hex: item.persistentID) {
                Button(L("history.undoTrack")) {
                    pendingUndo = UndoRequest(scope: .track(jobID: job.id, id), description: Lf("history.undoDescTrack", item.label))
                }
                .buttonStyle(.borderless)
                .disabled(state.isApplying)
            }
        }
    }

    private func icon(_ item: JobRow.Item) -> String {
        if item.undone { return "arrow.uturn.backward.circle" }
        switch item.state {
        case .verified: return "checkmark.circle.fill"
        case .verifyFailed, .failed: return "exclamationmark.triangle.fill"
        case .skippedChanged, .skippedNothing, .cancelled: return "minus.circle"
        case .planned, .writing: return "clock"
        }
    }

    private func color(_ item: JobRow.Item) -> Color {
        if item.undone { return .secondary }
        switch item.state {
        case .verified: return .green
        case .verifyFailed, .failed: return .red
        default: return .secondary
        }
    }
}
