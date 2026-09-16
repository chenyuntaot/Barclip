import AppKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class ViewRenderingTests: XCTestCase {
    func testRenderMenuAndSettingsInBothAppearances() async throws {
        let suite = "ClipboardHistory.Render.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let board = RenderPasteboard()
        let repository = HistoryRepository(fileURL: FileManager.default.temporaryDirectory
            .appending(path: suite).appending(path: "history.json"))
        let store = ClipboardStore(pasteboard: board, defaults: defaults, repository: repository)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
        try render(ClipboardMenuView().environment(store), name: "empty", appearance: .light)
        try render(ClipboardMenuView(initialKind: .image).environment(store), name: "empty-image", appearance: .light)
        board.text = "支持中文、多行与 Emoji 📝\n第二行保留原始格式。"
        board.changeCount += 1
        store.poll()
        await store.finishPendingSave()
        try render(ClipboardMenuView().environment(store), name: "history", appearance: .light)
        try render(ClipboardMenuView().environment(store), name: "history", appearance: .dark)
        board.png = TestPNG.pixel
        board.containsImage = true
        board.containsText = false
        board.changeCount += 1
        store.poll()
        await store.finishPendingSave()
        try render(ClipboardMenuView(initialKind: .image).environment(store), name: "images", appearance: .light)
        try render(ClipboardMenuView(isShowingSettings: true).environment(store), name: "settings-page", appearance: .light)
        try render(ClipboardSettingsView().environment(store).padding(16).frame(width: 360),
                   name: "settings", appearance: .light)
        try render(ClipboardSettingsView().environment(store).padding(16).frame(width: 360),
                   name: "settings", appearance: .dark)
    }

    func testHistoryRemainsVisibleUnderCompactMenuProposal() async throws {
        let suite = "ClipboardHistory.Layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let board = RenderPasteboard()
        let store = ClipboardStore(pasteboard: board, defaults: defaults,
            repository: HistoryRepository(fileURL: FileManager.default.temporaryDirectory
                .appending(path: suite).appending(path: "history.json")))
        for index in 1...3 {
            board.text = "可见历史记录 \(index)"
            board.changeCount += 1
            store.poll()
        }
        await store.finishPendingSave()
        let host = NSHostingController(rootView: ClipboardMenuView().environment(store))
        let compactSize = host.sizeThatFits(in: CGSize(width: 480, height: 0))
        // A menu host probes its minimum size. Three rows must not collapse into the toolbar.
        XCTAssertGreaterThanOrEqual(compactSize.height, 280,
            "有 3 条历史时，面板最小高度必须容纳可见列表；实际 \(compactSize.height)")
        XCTAssertGreaterThanOrEqual(compactSize.height, 320,
            "侧栏要同时放下分类按钮和左下角操作；实际 \(compactSize.height)")
        try render(ClipboardMenuView().environment(store).frame(height: compactSize.height),
                   name: "compact-history", appearance: .light)
    }

    private func render<Content: View>(_ content: Content, name: String, appearance: ColorScheme) throws {
        let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, appearance))
        host.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory
            .appending(path: "ClipboardHistory-\(name)-\(appearance == .dark ? "dark" : "light").png"))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
}

@MainActor
private final class RenderPasteboard: PasteboardAccess {
    var changeCount = 0
    var isAccessDenied = false
    var containsText = true
    var containsImage = false
    var text: String?
    var png: Data?
    func readText() -> String? { text }
    func readPNG() -> Data? { png }
    func writeText(_ text: String) -> Bool { self.text = text; changeCount += 1; return true }
    func writePNG(_ data: Data) -> Bool { png = data; changeCount += 1; return true }
}
