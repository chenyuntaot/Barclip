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
        try render(ClipboardMenuView(isShowingAbout: true).environment(store), name: "about-page", appearance: .light)
        try render(ClipboardSettingsView().environment(store).padding(16).frame(width: 360),
                   name: "settings", appearance: .light)
        try render(ClipboardSettingsView().environment(store).padding(16).frame(width: 360),
                   name: "settings", appearance: .dark)
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about", appearance: .light)
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about", appearance: .dark)
        try render(MenuBarExtraLabel().padding(8), name: "menu-bar-icon", appearance: .light)
        try render(MenuBarExtraLabel().padding(8), name: "menu-bar-icon", appearance: .dark)
        try render(ClipboardMenuView().environment(store), name: "empty-en", appearance: .light,
                   locale: Locale(identifier: "en"))
        try render(ClipboardSettingsView().environment(store).padding(16).frame(width: 360),
                   name: "settings-en", appearance: .light, locale: Locale(identifier: "en"))
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about-en", appearance: .light, locale: Locale(identifier: "en"))
    }

    func testAppInfoExposesAboutMetadata() {
        XCTAssertEqual(AppInfo.displayName, "Barclip")
        XCTAssertEqual(AppInfo.developer, "陈云涛")
        XCTAssertEqual(AppInfo.contactEmail, "chenyuntao0123@icloud.com")
        XCTAssertEqual(AppInfo.mailtoURL.absoluteString, "mailto:chenyuntao0123@icloud.com")
        XCTAssertEqual(AppInfo.repositoryURL.absoluteString, "https://github.com/chenyuntaot/Barclip")
        XCTAssertEqual(AppInfo.copyright, "© 2026 陈云涛")
        XCTAssertFalse(AppInfo.shortVersion.isEmpty)
        XCTAssertFalse(AppInfo.buildNumber.isEmpty)
        XCTAssertEqual(AppInfo.versionLabel, "\(AppInfo.shortVersion) (\(AppInfo.buildNumber))")
    }

    func testBundleUsesComposerAppIcon() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertGreaterThan(NSApplication.shared.applicationIconImage.size.width, 0)
        let menuBarIcon = try XCTUnwrap(NSImage(named: "MenuBarIcon"), "菜单栏应使用模板剪贴板图标")
        XCTAssertGreaterThan(menuBarIcon.size.width, 0)
        XCTAssertTrue(menuBarIcon.isTemplate, "菜单栏图标必须按模板着色，才能适配浅色和深色状态栏")
    }

    func testEnglishAndChineseCatalogEntriesResolve() {
        let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        XCTAssertNotNil(englishBundle, "编译产物应包含 en.lproj，系统语言为英文时才能切换界面")
        let english = englishBundle ?? .main
        XCTAssertEqual(String(localized: "设置", bundle: english), "Settings")
        XCTAssertEqual(String(localized: "文本", bundle: english), "Text")
        XCTAssertEqual(String(localized: "图片", bundle: english), "Images")
        XCTAssertEqual(String(localized: "清空历史", bundle: english), "Clear History")
        XCTAssertEqual(String(localized: "退出后清空", bundle: english), "Clear on Quit")
        XCTAssertEqual(String(localized: "磁盘缓存", bundle: english), "Disk Cache")
        XCTAssertEqual(String(localized: "文件夹地址", bundle: english), "Folder Path")
        XCTAssertEqual(String(localized: "关于我们", bundle: english), "About")
        XCTAssertEqual(String(localized: "已复制，可使用 ⌘V 粘贴。", bundle: english), "Copied. Paste with ⌘V.")
        XCTAssertEqual(ClipboardStore.StatusMessage.copied.allowsRetry, false)
        XCTAssertEqual(ClipboardStore.StatusMessage.pasteboardReadFailed.allowsRetry, true)
    }

    func testSettingsFooterKeepsAboutEntryVisible() throws {
        let suite = "ClipboardHistory.AboutFooter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = ClipboardStore(
            pasteboard: RenderPasteboard(),
            defaults: defaults,
            repository: HistoryRepository(fileURL: FileManager.default.temporaryDirectory
                .appending(path: suite).appending(path: "history.json"))
        )
        let host = NSHostingController(rootView: ClipboardSettingsView()
            .environment(store)
            .environment(\.locale, Locale(identifier: "zh_Hans"))
            .frame(width: 360))
        let size = host.sizeThatFits(in: CGSize(width: 360, height: 0))
        XCTAssertGreaterThan(size.height, 330,
            "设置页底部需要放下程序版本、关于我们和版权；实际 \(size.height)")
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
        let host = NSHostingController(rootView: ClipboardMenuView().environment(store)
            .environment(\.locale, Locale(identifier: "zh_Hans")))
        let compactSize = host.sizeThatFits(in: CGSize(width: 480, height: 0))
        // A menu host probes its minimum size. Three rows must not collapse into the toolbar.
        XCTAssertGreaterThanOrEqual(compactSize.height, 280,
            "有 3 条历史时，面板最小高度必须容纳可见列表；实际 \(compactSize.height)")
        XCTAssertGreaterThanOrEqual(compactSize.height, 320,
            "侧栏要同时放下分类按钮和左下角操作；实际 \(compactSize.height)")
        try render(ClipboardMenuView().environment(store).frame(height: compactSize.height),
                   name: "compact-history", appearance: .light)
    }

    private func render<Content: View>(
        _ content: Content,
        name: String,
        appearance: ColorScheme,
        locale: Locale = Locale(identifier: "zh_Hans")
    ) throws {
        let host = NSHostingView(rootView: content
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, appearance)
            .environment(\.locale, locale))
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
