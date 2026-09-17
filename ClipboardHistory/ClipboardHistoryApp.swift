import AppKit
import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ClipboardMenuView()
                .environment(delegate.store)
                .environment(delegate.fileStore)
        } label: {
            MenuBarExtraLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarExtraLabel: View {
    var body: some View {
        ClipboardGlyph(pointSize: 22)
            .accessibilityLabel("Barclip")
    }
}

struct ClipboardGlyph: View {
    var pointSize: CGFloat = 18

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: pointSize, height: pointSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: ClipboardStore
    let fileStore: FileStagingStore
    private var dropShelf: DropShelfController?
    private var testPasteboard: NSPasteboard?
    private var testDirectory: URL?
    private var testSuite: String?

    override init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--isolated-ui-check") {
            let suite = "ClipboardHistory.UICheck.\(UUID().uuidString)"
            if let defaults = UserDefaults(suiteName: suite) {
                let board = NSPasteboard.withUniqueName()
                let directory = FileManager.default.temporaryDirectory.appending(path: suite)
                testPasteboard = board
                testDirectory = directory
                testSuite = suite
                store = ClipboardStore(
                    pasteboard: PasteboardService(pasteboard: board),
                    defaults: defaults,
                    repository: HistoryRepository(fileURL: directory.appending(path: "history.json"))
                )
                fileStore = FileStagingStore(
                    defaults: defaults,
                    repository: FileStagingRepository(fileURL: directory.appending(path: "file-staging.json"))
                )
                super.init()
                board.setString("这是一条用于界面验证的模拟文本。\n支持中文、多行和 Emoji 📝", forType: .string)
                return
            }
        }
        #endif
        store = ClipboardStore()
        fileStore = FileStagingStore()
        super.init()
        dropShelf = DropShelfController(store: fileStore)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Unit tests use isolated pasteboards and must not capture the user's clipboard.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.start()
            fileStore.start()
            dropShelf?.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.stop()
        fileStore.endExport()
        dropShelf?.stop()
        Task {
            await store.finishPendingSave()
            await fileStore.finishPendingSave()
            if store.storageError == .save || fileStore.storageError == .save {
                let alert = NSAlert()
                alert.messageText = String(localized: "本机缓存尚未成功更新")
                alert.informativeText = String(localized: "现在退出可能丢失最新记录或保留旧缓存。可以返回后重试。")
                alert.addButton(withTitle: String(localized: "返回"))
                alert.addButton(withTitle: String(localized: "仍然退出"))
                if alert.runModal() == .alertFirstButtonReturn {
                    store.start()
                    fileStore.start()
                    dropShelf?.start()
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        dropShelf?.stop()
        testPasteboard?.releaseGlobally()
        if let testSuite { UserDefaults.standard.removePersistentDomain(forName: testSuite) }
        if let testDirectory, FileManager.default.fileExists(atPath: testDirectory.path) {
            do {
                try FileManager.default.removeItem(at: testDirectory)
            } catch {
                NSLog("Unable to remove isolated UI check cache")
            }
        }
    }
}
