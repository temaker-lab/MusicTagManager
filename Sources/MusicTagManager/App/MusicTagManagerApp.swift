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
                .task {
                    UpdateFeature.start()
                    await state.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        // 창 크기가 콘텐츠 크기를 따라가게 한다 → 온보딩은 작게, 대시보드는 크게.
        .windowResizability(.contentSize)
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
                ProgressView(L("root.launching")).modifier(MainWindowFrame())
            case .onboarding:
                // 온보딩은 메인 창을 꽉 채우지 않도록 작은 고정 크기로 (≈ 메인의 2/3)
                OnboardingView().frame(width: 800, height: 600)
            case .ready:
                DashboardView().modifier(MainWindowFrame())
            case .failed(let message):
                ContentUnavailableView(L("root.failed.title"), systemImage: "exclamationmark.triangle", description: Text(message))
                    .modifier(MainWindowFrame())
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

/// 메인 화면(대시보드 등)의 창 크기: 최소 1180×760, 기본 이 크기, 사용자가 더 크게 조절 가능.
/// 온보딩 단계는 이 프레임 대신 작은 고정 크기를 쓴다.
private struct MainWindowFrame: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(minWidth: 1180, idealWidth: 1180, maxWidth: .infinity,
                      minHeight: 760, idealHeight: 760, maxHeight: .infinity)
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
