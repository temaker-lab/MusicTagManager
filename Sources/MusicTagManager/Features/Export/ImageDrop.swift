import AppKit
import UniformTypeIdentifiers

/// 끌어 놓기·붙여넣기로 받은 이미지를 파일로 (Finder 파일, 브라우저 이미지, 클립보드)
enum ImageDrop {
    static let types: [UTType] = [.fileURL, .image]

    @MainActor
    static func load(_ providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadFileURL(provider), NSImage(contentsOf: url) != nil {
                return url
            }
            if provider.canLoadObject(ofClass: NSImage.self), let image = await loadImage(provider) {
                return write(image)
            }
        }
        return nil
    }

    @MainActor
    static func fromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first, NSImage(contentsOf: url) != nil {
            return url
        }
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        return write(image)
    }

    /// 임시 PNG 파일 (앱이 저장할 때 데이터 폴더로 복사함)
    static func write(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mtm-drop-\(UUID().uuidString).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func loadImage(_ provider: NSItemProvider) async -> NSImage? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in continuation.resume(returning: image as? NSImage) }
        }
    }
}
