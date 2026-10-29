import AppKit
import SwiftUI

@main
struct MusicTagManagerApp: App {
    @State private var state = AppState()

    init() {
        // SwiftPM 실행 파일로 바로 실행해도 일반 앱처럼 창이 뜨도록
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("MusicTag Manager", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    UpdateFeature.start()
                    await state.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // 앱 메뉴 'MusicTag Manager' > 업데이트 확인… (설정·링크된 경우에만 표시)
            CommandGroup(after: .appInfo) {
                if UpdateFeature.isAvailable {
                    Button(L("update.check")) { UpdateFeature.checkForUpdates() }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(state)
                .themed(state.settings.appearance)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Group {
            switch state.phase {
            case .launching:
                ProgressView(L("root.launching"))
            case .onboarding:
                OnboardingView()
            case .ready:
                DashboardView()
            case .failed(let message):
                ContentUnavailableView(L("root.failed.title"), systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .themed(state.settings.appearance)
        .overlay {
            if let notice = state.completionNotice {
                CompletionDialog(notice: notice) { suppress in state.dismissCompletionNotice(suppress: suppress) }
            }
        }
        .alert(L("root.removedPlaylist.title"), isPresented: Binding(
            get: { !state.removedPlaylistNotice.isEmpty },
            set: { if !$0 { state.removedPlaylistNotice = [] } }
        )) {
            Button(L("common.ok")) { state.removedPlaylistNotice = [] }
        } message: {
            Text(Lf("root.removedPlaylist.msg", state.removedPlaylistNotice.joined(separator: ", ")))
        }
    }
}

/// 앱 창 가운데에 뜨는 적용 결과 알림
struct CompletionDialog: View {
    let notice: CompletionNotice
    let dismiss: (Bool) -> Void
    @State private var suppress = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {}  // 뒤 화면 클릭 막기
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(notice.isWarning ? .orange : .green)
                    Text(notice.title).font(.title3.bold())
                }
                Text(notice.summary).font(.body)
                Text(L("completion.detailNote"))
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Toggle(L("completion.dontShowAgain"), isOn: $suppress).toggleStyle(.checkbox)
                    Spacer()
                    Button(L("common.ok")) { dismiss(suppress) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}
