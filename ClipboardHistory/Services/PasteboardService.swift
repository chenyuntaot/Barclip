import AppKit

@MainActor
protocol PasteboardAccess {
    var changeCount: Int { get }
    var isAccessDenied: Bool { get }
    var containsText: Bool { get }
    func readText() -> String?
    func writeText(_ text: String) -> Bool
}

@MainActor
final class PasteboardService: PasteboardAccess {
    private let pasteboard: NSPasteboard

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
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        return types.contains(.string) && !types.contains(.fileURL)
            && !excluded.contains { types.contains(NSPasteboard.PasteboardType($0)) }
    }

    func readText() -> String? { pasteboard.string(forType: .string) }

    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
