import AppKit

@MainActor
protocol PasteboardAccess {
    var changeCount: Int { get }
    var isAccessDenied: Bool { get }
    var containsText: Bool { get }
    var containsImage: Bool { get }
    func readText() -> String?
    func readPNG() -> Data?
    func writeText(_ text: String) -> Bool
    func writePNG(_ data: Data) -> Bool
}

@MainActor
final class PasteboardService: PasteboardAccess {
    private let pasteboard: NSPasteboard
    private static let jpegType = NSPasteboard.PasteboardType("public.jpeg")

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var isAccessDenied: Bool {
        if #available(macOS 15.4, *) {
            return pasteboard.accessBehavior == .alwaysDeny
        }
        return false
    }

    var containsText: Bool {
        let types = pasteboard.types ?? []
        return types.contains(.string) && isUnmarked(types) && !types.contains(.fileURL)
    }

    var containsImage: Bool {
        let types = pasteboard.types ?? []
        return Self.imageTypes.contains(where: types.contains) && isUnmarked(types)
    }

    func readText() -> String? { pasteboard.string(forType: .string) }

    func readPNG() -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty { return png }
        for type in [.tiff, Self.jpegType] as [NSPasteboard.PasteboardType] {
            guard let data = pasteboard.data(forType: type),
                  let image = NSImage(data: data) else { continue }
            if let png = Self.pngData(from: image), !png.isEmpty { return png }
        }
        return nil
    }

    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func writePNG(_ data: Data) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    private func isUnmarked(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        return !excluded.contains { types.contains(NSPasteboard.PasteboardType($0)) }
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, jpegType]

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
