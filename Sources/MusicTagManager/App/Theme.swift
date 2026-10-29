import AppKit
import SwiftUI

/// 화면 테마 (설정 > 화면, 상단 오른쪽 버튼)
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("theme.system")
        case .light: return L("theme.light")
        case .dark: return L("theme.dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// 실제로 쓸 색 구성. '시스템 설정'은 현재 macOS 화면 모드를 직접 읽어 정한다.
    /// (preferredColorScheme(nil)은 한 번 다크/라이트를 지정한 뒤에는 시스템 모드로 돌아오지 않는다)
    func resolvedScheme(system: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return system
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension ColorScheme {
    /// 표·메뉴·시트 같은 AppKit 요소도 같은 테마로
    var nsAppearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}

/// macOS 시스템 화면 모드(라이트/다크)를 추적한다. 앱 자체 테마 설정과 무관하게 전역 설정을 읽는다.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var scheme: ColorScheme = SystemAppearance.current()
    private var observer: NSObjectProtocol?

    private init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SystemAppearance.shared.scheme = SystemAppearance.current() }
        }
    }

    private static func current() -> ColorScheme {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
            ? .dark : .light
    }
}

/// 설정의 화면 테마를 적용 (SwiftUI 색 구성 + AppKit 표·메뉴·시트)
struct ThemeModifier: ViewModifier {
    let mode: AppearanceMode
    @State private var system = SystemAppearance.shared

    func body(content: Content) -> some View {
        let scheme = mode.resolvedScheme(system: system.scheme)
        content
            .preferredColorScheme(scheme)
            .environment(\.colorScheme, scheme)
            .modifier(PaletteProvider())
            .onAppear { NSApplication.shared.appearance = scheme.nsAppearance }
            .onChange(of: scheme) { _, scheme in NSApplication.shared.appearance = scheme.nsAppearance }
    }
}

extension View {
    func themed(_ mode: AppearanceMode) -> some View {
        modifier(ThemeModifier(mode: mode))
    }
}

/// 남색·청록 계열 팔레트 (다크: 짙은 남색 배경, 기본: 연한 라벤더 배경 + 흰 카드)
struct Palette {
    let background: Color
    let card: Color
    let cardBorder: Color
    /// 강조 카드(남색 그라디언트) — 두 테마 모두 남색
    let strongStart: Color
    let strongEnd: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let accentBlue: Color
    let accentSlate: Color
    let accentDeep: Color
    let track: Color
    let success: Color
    let warning: Color
    let danger: Color
    let shadow: Color

    static let dark = Palette(
        background: Color(hex: 0x0A1628), card: Color(hex: 0x10223F), cardBorder: Color(hex: 0x1F3A66),
        strongStart: Color(hex: 0x16305C), strongEnd: Color(hex: 0x0E1F3E),
        text: Color(hex: 0xE6EDF8), secondaryText: Color(hex: 0x8C9DBB),
        accent: Color(hex: 0x2DD4E8), accentBlue: Color(hex: 0x4C6FFF), accentSlate: Color(hex: 0x5B79B8),
        accentDeep: Color(hex: 0x24406E), track: Color(hex: 0x1B3157),
        success: Color(hex: 0x34D399), warning: Color(hex: 0xFBBF24), danger: Color(hex: 0xF87171),
        shadow: Color(hex: 0x2DD4E8).opacity(0.08))

    static let light = Palette(
        background: Color(hex: 0xE7EAF6), card: Color(hex: 0xF8F9FD), cardBorder: Color(hex: 0xDCE1F0),
        strongStart: Color(hex: 0x1E3366), strongEnd: Color(hex: 0x14244A),
        text: Color(hex: 0x1B2547), secondaryText: Color(hex: 0x6A7493),
        accent: Color(hex: 0x14B8D0), accentBlue: Color(hex: 0x3F5EEB), accentSlate: Color(hex: 0x6D86C4),
        accentDeep: Color(hex: 0x2A3C6E), track: Color(hex: 0xE2E7F4),
        success: Color(hex: 0x10A36F), warning: Color(hex: 0xD99A06), danger: Color(hex: 0xE04848),
        shadow: Color.black.opacity(0.08))

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// 현재 색 구성에 맞는 팔레트를 하위 뷰에 넣는다
struct PaletteProvider: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .environment(\.palette, Palette.of(scheme))
            .tint(Palette.of(scheme).accentBlue)
    }
}

/// 둥근 카드 (첨부 디자인의 카드)
struct CardModifier: ViewModifier {
    @Environment(\.palette) private var palette
    var strong = false
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .foregroundStyle(strong ? Color.white : palette.text)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(strong
                          ? AnyShapeStyle(LinearGradient(colors: [palette.strongStart, palette.strongEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(palette.card))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(strong ? Color.white.opacity(0.06) : palette.cardBorder, lineWidth: 1)
            }
            .shadow(color: palette.shadow, radius: 14, y: 6)
    }
}

extension View {
    func card(strong: Bool = false, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(strong: strong, padding: padding))
    }

    /// 같은 줄의 카드끼리 높이·너비를 맞추는 카드 (가용 공간을 가득 채움)
    func cardFill(strong: Bool = false, padding: CGFloat = 16) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(CardModifier(strong: strong, padding: padding))
    }
}

/// 상단 알약 탭·필터 버튼
struct PillButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    var selected: Bool
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .callout : .body.weight(.medium))
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 4 : 6)
            .foregroundStyle(selected ? palette.accent : palette.text.opacity(0.85))
            .background {
                Capsule().fill(selected ? palette.accent.opacity(0.14) : palette.card.opacity(configuration.isPressed ? 0.6 : 1))
            }
            .overlay {
                Capsule().strokeBorder(selected ? palette.accent : palette.cardBorder, lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? palette.accent.opacity(0.35) : .clear, radius: 6)
            .contentShape(Capsule())
    }
}

/// 하단 액션 영역의 보조 버튼(취소·닫기·거부·직접 수정 등) 공통 스타일.
/// 밝은 회백색 글자 + 중간 회색 배경 + 얇은 테두리로 가시성을 높인다.
/// '적용'·'식별'·'승인'·'저장 후 적용' 같은 강조(파랑/보라/기본) 버튼에는 적용하지 않는다.
struct NeutralActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Color(hex: 0xE4E7EC))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: configuration.isPressed ? 0x3A3D45 : 0x454852))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// 상단 오른쪽 테마 전환 (달 · 반쪽 · 해)
struct AppearanceSwitcher: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach([AppearanceMode.dark, .system, .light]) { mode in
                Button {
                    state.settings.appearance = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 13))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(state.settings.appearance == mode ? palette.accent : palette.secondaryText)
                        .background(Circle().fill(state.settings.appearance == mode ? palette.accent.opacity(0.15) : .clear))
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
    }
}
