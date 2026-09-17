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
        let files = FileStagingStore(
            defaults: defaults,
            repository: FileStagingRepository(fileURL: FileManager.default.temporaryDirectory
                .appending(path: suite).appending(path: "file-staging.json"))
        )
        XCTAssertEqual(NSApplication.shared.activationPolicy(), .accessory)
        try render(menu(store, files), name: "empty", appearance: .light)
        try render(menu(store, files, initialKind: .image), name: "empty-image", appearance: .light)
        try render(menu(store, files, showsFiles: true), name: "empty-files", appearance: .light)
        try render(menu(store, files, showsFiles: true), name: "empty-files", appearance: .dark)
        board.text = "支持中文、多行与 Emoji 📝\n第二行保留原始格式。"
        board.changeCount += 1
        store.poll()
        await store.finishPendingSave()
        try render(menu(store, files), name: "history", appearance: .light)
        try render(menu(store, files), name: "history", appearance: .dark)
        board.png = TestPNG.pixel
        board.containsImage = true
        board.containsText = false
        board.changeCount += 1
        store.poll()
        await store.finishPendingSave()
        try render(menu(store, files, initialKind: .image), name: "images", appearance: .light)
        try render(menu(store, files, isShowingSettings: true), name: "settings-page", appearance: .light)
        try render(menu(store, files, isShowingAbout: true), name: "about-page", appearance: .light)
        try render(ClipboardSettingsView().environment(store).environment(files).padding(16).frame(width: 360),
                   name: "settings", appearance: .light)
        try render(ClipboardSettingsView().environment(store).environment(files).padding(16).frame(width: 360),
                   name: "settings", appearance: .dark)
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about", appearance: .light)
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about", appearance: .dark)
        try render(MenuBarExtraLabel().padding(8), name: "menu-bar-icon", appearance: .light)
        try render(MenuBarExtraLabel().padding(8), name: "menu-bar-icon", appearance: .dark)
        try render(menu(store, files), name: "empty-en", appearance: .light,
                   locale: Locale(identifier: "en"))
        try render(ClipboardSettingsView().environment(store).environment(files).padding(16).frame(width: 360),
                   name: "settings-en", appearance: .light, locale: Locale(identifier: "en"))
        try render(ClipboardAboutView().padding(16).frame(width: 360),
                   name: "about-en", appearance: .light, locale: Locale(identifier: "en"))
        try render(menu(store, files, showsFiles: true), name: "empty-files-en", appearance: .light,
                   locale: Locale(identifier: "en"))
        try render(DropShelfView(isTargeted: .constant(false), onDrop: { _ in })
            .frame(width: MenuBarDropAnchor.shelfSize.width, height: MenuBarDropAnchor.shelfSize.height), name: "drop-shelf", appearance: .light)
        try render(DropShelfView(isTargeted: .constant(true), onDrop: { _ in })
            .frame(width: MenuBarDropAnchor.shelfSize.width, height: MenuBarDropAnchor.shelfSize.height), name: "drop-shelf-targeted", appearance: .light)
        try render(DropShelfView(isTargeted: .constant(false), onDrop: { _ in })
            .frame(width: MenuBarDropAnchor.shelfSize.width, height: MenuBarDropAnchor.shelfSize.height), name: "drop-shelf", appearance: .dark)
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
        XCTAssertEqual(String(localized: "文件", bundle: english), "Files")
        XCTAssertEqual(String(localized: "清空历史", bundle: english), "Clear History")
        XCTAssertEqual(String(localized: "清空暂存", bundle: english), "Clear Staging")
        XCTAssertEqual(String(localized: "暂无暂存文件", bundle: english), "No Staged Files")
        XCTAssertEqual(String(localized: "拖到此处暂存", bundle: english), "Drop to Stage")
        XCTAssertEqual(String(localized: "暂存区只记录文件引用。", bundle: english), "Staging only stores file references.")
        XCTAssertEqual(String(localized: "预览", bundle: english), "Preview")
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
        let files = FileStagingStore(
            defaults: defaults,
            repository: FileStagingRepository(fileURL: FileManager.default.temporaryDirectory
                .appending(path: suite).appending(path: "file-staging.json"))
        )
        let host = NSHostingController(rootView: ClipboardSettingsView()
            .environment(store)
            .environment(files)
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
        let files = FileStagingStore(
            defaults: defaults,
            repository: FileStagingRepository(fileURL: FileManager.default.temporaryDirectory
                .appending(path: suite).appending(path: "file-staging.json"))
        )
        for index in 1...3 {
            board.text = "可见历史记录 \(index)"
            board.changeCount += 1
            store.poll()
        }
        await store.finishPendingSave()
        let host = NSHostingController(rootView: menu(store, files)
            .environment(\.locale, Locale(identifier: "zh_Hans")))
        let compactSize = host.sizeThatFits(in: CGSize(width: 480, height: 0))
        // A menu host probes its minimum size. Three rows must not collapse into the toolbar.
        XCTAssertGreaterThanOrEqual(compactSize.height, 280,
            "有 3 条历史时，面板最小高度必须容纳可见列表；实际 \(compactSize.height)")
        XCTAssertGreaterThanOrEqual(compactSize.height, 320,
            "侧栏要同时放下分类按钮和左下角操作；实际 \(compactSize.height)")
        try render(menu(store, files).frame(height: compactSize.height),
                   name: "compact-history", appearance: .light)
        let file = FileManager.default.temporaryDirectory.appending(path: "\(suite)-staged.txt")
        try Data("staged".utf8).write(to: file)
        files.stage([file])
        try render(menu(store, files, showsFiles: true), name: "files", appearance: .light)
        try render(menu(store, files, showsFiles: true), name: "files", appearance: .dark)
        let imageFile = FileManager.default.temporaryDirectory.appending(path: "\(suite)-staged.png")
        try TestPNG.pixel.write(to: imageFile)
        files.stage([imageFile])
        try render(menu(store, files, showsFiles: true), name: "files-image", appearance: .light)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.removeItem(at: imageFile)
        files.refresh()
        try render(menu(store, files, showsFiles: true), name: "files-missing", appearance: .light)
    }

    private func menu(
        _ store: ClipboardStore,
        _ files: FileStagingStore,
        initialKind: ClipboardKind = .text,
        isShowingSettings: Bool = false,
        isShowingAbout: Bool = false,
        showsFiles: Bool = false
    ) -> some View {
        ClipboardMenuView(
            initialKind: initialKind,
            isShowingSettings: isShowingSettings,
            isShowingAbout: isShowingAbout,
            showsFiles: showsFiles
        )
        .environment(store)
        .environment(files)
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
