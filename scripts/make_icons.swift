// 앱 아이콘 샘플을 그려 PNG로 저장한다.
// 사용: swift scripts/make_icons.swift <출력 폴더>
import AppKit
import SwiftUI

let navy = Color(red: 0x0A / 255, green: 0x16 / 255, blue: 0x28 / 255)
let navy2 = Color(red: 0x16 / 255, green: 0x30 / 255, blue: 0x5C / 255)
let cyan = Color(red: 0x2D / 255, green: 0xD4 / 255, blue: 0xE8 / 255)
let blue = Color(red: 0x4C / 255, green: 0x6F / 255, blue: 0xFF / 255)
let violet = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255)
let magenta = Color(red: 0xC0 / 255, green: 0x4D / 255, blue: 0xFF / 255)
let green = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)

/// macOS 아이콘 격자: 1024 캔버스, 824 둥근 사각형
struct IconBase<Content: View>: View {
    var background: AnyShapeStyle
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            content.frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
    }
}

let navyGradient = AnyShapeStyle(LinearGradient(colors: [navy2, navy], startPoint: .top, endPoint: .bottom))

/// 가격표 모양 (태그)
struct TagShape: Shape {
    func path(in r: CGRect) -> Path {
        let notch = r.width * 0.30
        let radius = r.height * 0.14
        var p = Path()
        p.move(to: CGPoint(x: r.minX + notch, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + notch, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// A. 음표가 들어간 태그 — "음악 태그 정리" 그대로
struct IconA: View {
    var body: some View {
        IconBase(background: navyGradient) {
            ZStack {
                TagShape()
                    .fill(LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 560, height: 360)
                    .rotationEffect(.degrees(-30))
                    .shadow(color: cyan.opacity(0.45), radius: 30)
                Circle().fill(navy).frame(width: 54, height: 54)
                    .offset(x: -170, y: 98)
                Image(systemName: "music.note")
                    .font(.system(size: 230, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-30))
                    .offset(x: 50, y: -28)
            }
        }
    }
}

// B. 빈 앨범커버가 채워지는 모습 — 점선 칸 + 음표 + 체크 배지
struct IconB: View {
    var body: some View {
        IconBase(background: navyGradient) {
            ZStack {
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 440, height: 440)
                    .offset(x: -30, y: 30)
                    .shadow(color: cyan.opacity(0.4), radius: 30)
                Image(systemName: "music.note")
                    .font(.system(size: 220, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: -30, y: 30)
                Circle().fill(green)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 110, weight: .black)).foregroundStyle(.white))
                    .overlay(Circle().strokeBorder(navy, lineWidth: 22))
                    .frame(width: 230, height: 230)
                    .offset(x: 200, y: -190)
            }
        }
    }
}

// C. 레코드판 + 돋보기 — 식별(찾기)에 초점
struct IconC: View {
    var body: some View {
        IconBase(background: navyGradient) {
            ZStack {
                ZStack {
                    Circle().fill(Color(white: 0.08))
                    ForEach(0..<6) { i in
                        Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 3)
                            .padding(CGFloat(40 + i * 30))
                    }
                    Circle().fill(LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 190, height: 190)
                    Circle().fill(navy).frame(width: 30, height: 30)
                }
                .frame(width: 520, height: 520)
                .offset(x: -60, y: -40)
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 44).frame(width: 260, height: 260)
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 216, height: 216)
                    Capsule().fill(.white).frame(width: 52, height: 170)
                        .rotationEffect(.degrees(-45))
                        .offset(x: 150, y: 150)
                }
                .offset(x: 140, y: 130)
                .shadow(color: .black.opacity(0.4), radius: 20)
            }
        }
    }
}

// D. 음표 + 반짝임 — 자동으로 채워 주는 정리 도구 (보라 그라디언트)
struct IconD: View {
    var body: some View {
        IconBase(background: AnyShapeStyle(LinearGradient(colors: [violet, blue, Color(red: 0.05, green: 0.12, blue: 0.3)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))) {
            ZStack {
                Image(systemName: "music.note")
                    .font(.system(size: 400, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.white, cyan], startPoint: .top, endPoint: .bottom))
                    .offset(x: -30, y: 20)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                Image(systemName: "sparkle")
                    .font(.system(size: 170, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 230, y: -220)
                Image(systemName: "sparkle")
                    .font(.system(size: 90, weight: .bold))
                    .foregroundStyle(cyan)
                    .offset(x: 120, y: -310)
            }
        }
    }
}

@MainActor
func save<V: View>(_ view: V, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("렌더링 실패") }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icons", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    save(IconA(), to: output.appendingPathComponent("icon-A-tag.png"))
    save(IconB(), to: output.appendingPathComponent("icon-B-cover.png"))
    save(IconC(), to: output.appendingPathComponent("icon-C-identify.png"))
    save(IconD(), to: output.appendingPathComponent("icon-D-sparkle.png"))
}
