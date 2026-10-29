import MTMCore
import SwiftUI

/// 검수표 가져오기 결과: 고친 값·거절은 이미 반영, 승인은 여기서 적용
struct ReviewSheetImportView: View {
    @Environment(AppState.self) private var state
    let result: ReviewSheet.ImportResult
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("import.title")).font(.title2.bold())
            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow { Text(L("import.overridesLabel")); Text(Lf("import.overridesValue", result.overrides.count)).bold() }
                GridRow { Text(L("import.rejectLabel")); Text(Lf("import.rejectValue", result.reject.count)).bold() }
                GridRow { Text(L("import.approveLabel")); Text(Lf("import.approveValue", result.approve.count)).bold() }
                GridRow { Text(L("import.unchangedLabel")); Text(Lf("import.unchangedValue", result.unchanged)) }
            }
            if !result.errors.isEmpty {
                Text(Lf("import.errorsTitle", result.errors.count)).font(.headline).foregroundStyle(.red)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.errors, id: \.self) { Text($0).font(.callout) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            HStack {
                Spacer()
                Button(L("common.close"), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NeutralActionButtonStyle())
                Button(Lf("import.applyApproved", result.approve.count)) {
                    let ids = Set(result.approve)
                    dismiss()
                    Task { await state.apply(ids) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result.approve.isEmpty || state.isApplying)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

extension ReviewSheet.ImportResult: @retroactive Identifiable {
    public var id: String { "\(overrides.count)-\(approve.count)-\(reject.count)-\(errors.count)-\(unchanged)" }
}
