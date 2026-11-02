// DMG '드래그하여 설치' 배경 이미지 생성 → Resources/dmg-background.png (+@2x)
// 사용: swift scripts/make_dmg_background.swift
import AppKit

let W = 660, H = 420
func draw(scale: Int) -> Data {
    let px = W * scale, py = H * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // 배경: 아주 옅은 세로 그라디언트
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1),
        CGColor(red: 0.93, green: 0.94, blue: 0.98, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: 0), options: [])

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, centerX: CGFloat, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let a = NSAttributedString(string: s, attributes: attrs)
        let sz = a.size()
        a.draw(at: NSPoint(x: centerX - sz.width / 2, y: y))
    }

    // 제목 · 안내 문구 (Finder 좌표가 아니라 그림 좌표: y는 아래가 0)
    text("MusicTag Manager", 22, .bold, NSColor(white: 0.12, alpha: 1), centerX: CGFloat(W) / 2, y: CGFloat(H) - 56)
    text("아이콘을 응용 프로그램 폴더로 드래그하세요", 13, .medium, NSColor(white: 0.35, alpha: 1), centerX: CGFloat(W) / 2, y: CGFloat(H) - 84)
    text("Drag the icon to the Applications folder", 11.5, .regular, NSColor(white: 0.5, alpha: 1), centerX: CGFloat(W) / 2, y: CGFloat(H) - 104)

    // 가운데 화살표 (두 아이콘 사이, 아이콘 중심 y≈185(Finder,위에서) → 그림 y≈ H-185)
    let arrowY = CGFloat(H) - 185
    let path = NSBezierPath()
    path.lineWidth = 7
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    NSColor(red: 0.49, green: 0.36, blue: 1.0, alpha: 0.9).setStroke()  // 앱 보라색 톤
    path.move(to: NSPoint(x: 270, y: arrowY))
    path.line(to: NSPoint(x: 390, y: arrowY))
    path.stroke()
    let head = NSBezierPath()
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: 372, y: arrowY + 16))
    head.line(to: NSPoint(x: 392, y: arrowY))
    head.line(to: NSPoint(x: 372, y: arrowY - 16))
    head.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = FileManager.default.currentDirectoryPath
try! draw(scale: 1).write(to: URL(fileURLWithPath: "\(root)/Resources/dmg-background.png"))
try! draw(scale: 2).write(to: URL(fileURLWithPath: "\(root)/Resources/dmg-background@2x.png"))
print("생성: Resources/dmg-background.png (+@2x)")
