import AppKit
import MTMCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    /// 최초 실행(firstRun) 또는 설정에서 '다시 보기'(replay)
    var mode: OnboardingViewModel.Mode = .firstRun
    /// replay일 때 시트를 닫는 콜백
    var onClose: (() -> Void)?
    @State private var model: OnboardingViewModel?

    var body: some View {
        Group {
            if let model {
                OnboardingContent(model: model)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if model == nil { model = OnboardingViewModel(state: state, mode: mode, onClose: onClose) }
        }
    }
}

private struct OnboardingContent: View {
    @Environment(AppState.self) private var state
    @Bindable var model: OnboardingViewModel

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            header(language: $state.settings.language)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            Divider()
            Group {
                switch model.step {
                case .welcome: welcome
                case .howItWorks: howItWorks
                case .permissions: permissions
                case .playlists: playlists
                }
            }
            // '사용 방법'은 2열 그리드라 더 넓은 폭을 쓴다
            .frame(maxWidth: model.step == .howItWorks ? 920 : 720, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            Divider()
            footer
                .padding(16)
        }
    }

    // MARK: - 상단 (단계 표시 + replay 닫기)

    private func header(language: Binding<AppLanguage>) -> some View {
        HStack(spacing: 16) {
            stepIndicator
            Spacer()
            // 최초 실행 때 설정에 들어가기 전에도 언어를 고를 수 있게 (설정 언어와 연동)
            Picker("", selection: language) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help(L("settings.general.language"))
            .accessibilityLabel(L("settings.general.language"))
            if model.mode == .replay {
                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("onb.footer.close"))
                .accessibilityLabel(L("onb.footer.close"))
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 20) {
            ForEach(Array(model.steps.enumerated()), id: \.element) { position, step in
                HStack(spacing: 6) {
                    Image(systemName: position < model.index ? "checkmark.circle.fill"
                          : position == model.index ? "\(position + 1).circle.fill" : "\(position + 1).circle")
                    Text(step.title)
                }
                .foregroundStyle(position == model.index ? Color.accentColor : .secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.callout)
    }

    // MARK: - 단계별 내용

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MusicTag Manager")
                .font(.largeTitle.bold())
            Text(L("onb.welcome.body"))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Label(L("onb.welcome.point1"), systemImage: "checkmark.shield")
            Label(L("onb.welcome.point2"), systemImage: "eye")
        }
    }

    /// 핵심 기능 흐름(스캔 → 식별 → 검토 → 적용)을 앱 화면 미리보기 + 상세 설명으로 안내한다.
    /// 이미지가 들어가면서 세로가 길어지지 않도록 2열 그리드로 배치한다.
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("onb.how.intro"))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)],
                      alignment: .leading, spacing: 14) {
                StepRow(mock: .scan, tint: .blue, title: L("onb.how.scan.title"),
                        details: [L("onb.how.scan.detail"), L("onb.how.scan.detail2")])
                StepRow(mock: .identify, tint: .purple, title: L("onb.how.identify.title"),
                        details: [L("onb.how.identify.detail"), L("onb.how.identify.detail2")])
                StepRow(mock: .review, tint: .orange, title: L("onb.how.review.title"),
                        details: [L("onb.how.review.detail"), L("onb.how.review.detail2")])
                StepRow(mock: .apply, tint: .green, title: L("onb.how.apply.title"),
                        details: [L("onb.how.apply.detail"), L("onb.how.apply.detail2")])
            }
            Label(L("onb.how.note"), systemImage: "arrow.uturn.backward.circle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("onb.perm.intro"))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            PermissionRow(
                title: L("onb.perm.automation.title"),
                detail: L("onb.perm.automation.detail"),
                status: model.automation,
                isWorking: model.isRequestingAutomation,
                request: { Task { await model.requestAutomation() } },
                openSettings: { Permissions.openSystemSettings(.automation) }
            )
            PermissionRow(
                title: L("onb.perm.media.title"),
                detail: L("onb.perm.media.detail"),
                status: model.media,
                isWorking: model.isRequestingMedia,
                request: { Task { await model.requestMedia() } },
                openSettings: { Permissions.openSystemSettings(.media) }
            )
            if let error = model.mediaError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 권한을 '나중에' 할 때 어떤 일이 생기는지 미리 안내 (거부 시 대안)
            if model.canSkipPermissions {
                Label(L("onb.perm.laterNote"), systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("onb.playlists.intro"))
                .font(.title3)
            PlaylistPickerView(model: model.picker)
        }
    }

    // MARK: - 하단 (이전 · 나중에 · 다음/시작/닫기)

    private var footer: some View {
        HStack {
            if !model.isFirstStep {
                Button(L("onb.footer.back")) { model.goBack() }
                    .disabled(model.isFinishing)
            }
            Spacer()
            if let hint = model.nextHint {
                Text(hint).font(.callout).foregroundStyle(.secondary)
            }
            if model.canSkipPermissions {
                Button(L("onb.footer.later")) { Task { await model.skipPermissions() } }
                    .buttonStyle(.link)
            }
            Button(primaryTitle) {
                Task { await model.goNext() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!primaryEnabled)
        }
    }

    private var primaryTitle: String {
        guard model.isLastStep else { return L("onb.footer.next") }
        return model.mode == .replay ? L("onb.footer.close") : L("onb.footer.start")
    }

    private var primaryEnabled: Bool {
        // replay의 마지막(닫기)은 항상 가능, 그 외는 단계 조건을 따른다
        if model.isLastStep, model.mode == .replay { return true }
        return model.canGoNext
    }
}

/// 핵심 기능 흐름 카드 (번호 · 아이콘 · 제목 · 설명)
private struct FlowCard: View {
    let number: Int
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15))
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// 핵심 기능 한 단계: 앱 화면 미리보기(목업) + 제목 + 상세 설명 2줄
private struct StepRow: View {
    let mock: MockKind
    let tint: Color
    let title: String
    let details: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MockScreen(kind: mock, tint: tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(tint)
                ForEach(details, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(line).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// 온보딩 '사용 방법'용 앱 화면 목업 (실제 UI를 축약해 표현 — 디자인 시스템과 같은 톤)
enum MockKind { case scan, identify, review, apply }

private struct MockScreen: View {
    let kind: MockKind
    let tint: Color

    var body: some View {
        Group {
            if let shot = Self.screenshot(for: kind) {
                // 실제 앱 화면 스크린샷 (어두운 틀 안에 전체가 보이도록 맞춤)
                Image(nsImage: shot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 172, height: 112)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.10)))
            } else {
                // 리소스를 찾지 못하면 기존 벡터 목업으로 대체
                content
                    .padding(10)
                    .frame(width: 172, height: 112, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
            }
        }
        .accessibilityHidden(true)
    }

    /// 앱 번들(Resources/Onboarding)에 포함된 실제 화면 스크린샷. 없으면 nil → 벡터 목업으로 대체.
    private static func screenshot(for kind: MockKind) -> NSImage? {
        let name: String
        switch kind {
        case .scan: name = "onb-scan"
        case .identify: name = "onb-identify"
        case .review: name = "onb-review"
        case .apply: name = "onb-apply"
        }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Onboarding")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .scan:
            VStack(alignment: .leading, spacing: 7) {
                ForEach([L("field.title"), L("field.artwork"), L("field.artist")], id: \.self) { field in
                    HStack(spacing: 6) {
                        bar(width: 64)
                        Spacer(minLength: 0)
                        chip(field, .orange)
                    }
                }
            }
        case .identify:
            VStack(alignment: .leading, spacing: 7) {
                idRow(L("level.high"), .green)
                idRow(L("level.medium"), .yellow)
                idRow(L("level.low"), .orange)
            }
        case .review:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.35)).frame(width: 46, height: 46)
                    .overlay(Image(systemName: "music.note").foregroundStyle(tint))
                VStack(alignment: .leading, spacing: 5) { bar(width: 92); bar(width: 64) }
                Spacer(minLength: 0)
                VStack(spacing: 5) { iconChip("checkmark", .green); iconChip("xmark", .red) }
            }
        case .apply:
            VStack(alignment: .leading, spacing: 9) {
                diffRow(field: L("field.title"))
                diffRow(field: L("field.artwork"))
            }
        }
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.45)).frame(width: width, height: 7)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .lineLimit(1).fixedSize()
    }

    /// 언어와 무관한 아이콘 칩 (승인 ✓ · 거부 ✕)
    private func iconChip(_ systemName: String, _ color: Color) -> some View {
        Image(systemName: systemName).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(Capsule().fill(color.opacity(0.18)))
    }

    private func idRow(_ level: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.35)).frame(width: 16, height: 16)
            bar(width: 70)
            Spacer(minLength: 0)
            chip(level, color)
        }
    }

    private func diffRow(field: String) -> some View {
        HStack(spacing: 6) {
            Text(field).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            chip("∅", .secondary)
            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.secondary)
            chip("✓", .green)
        }
    }
}

private struct HowItWorksPreview: View {
    let language: AppLanguage
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)],
                  alignment: .leading, spacing: 14) {
            StepRow(mock: .scan, tint: .blue, title: L("onb.how.scan.title"),
                    details: [L("onb.how.scan.detail"), L("onb.how.scan.detail2")])
            StepRow(mock: .identify, tint: .purple, title: L("onb.how.identify.title"),
                    details: [L("onb.how.identify.detail"), L("onb.how.identify.detail2")])
            StepRow(mock: .review, tint: .orange, title: L("onb.how.review.title"),
                    details: [L("onb.how.review.detail"), L("onb.how.review.detail2")])
            StepRow(mock: .apply, tint: .green, title: L("onb.how.apply.title"),
                    details: [L("onb.how.apply.detail"), L("onb.how.apply.detail2")])
        }
        .padding(24)
        .frame(width: 752)
        .onAppear { LocalizationManager.shared.language = language }
    }
}

#Preview("How it works (English)") { HowItWorksPreview(language: .english) }
#Preview("How it works (Korean)") { HowItWorksPreview(language: .korean) }

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    let isWorking: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(status.isGranted ? .green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .denied {
                    Text(L("onb.perm.denied"))
                        .font(.callout).foregroundStyle(.red)
                }
            }
            Spacer()
            if isWorking {
                ProgressView().controlSize(.small)
            } else if !status.isGranted {
                VStack(alignment: .trailing) {
                    Button(status == .denied ? L("onb.perm.recheck") : L("onb.perm.allow"), action: request)
                    if status == .denied {
                        Button(L("onb.perm.openSettings"), action: openSettings).buttonStyle(.link)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.isGranted ? L("onb.perm.granted.a11y") : "")
    }
}
