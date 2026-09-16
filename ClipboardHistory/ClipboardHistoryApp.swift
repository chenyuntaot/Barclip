import SwiftUI

@main
struct ClipboardHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("剪贴板历史", systemImage: "clipboard") {
            ClipboardMenuView().environment(delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: ClipboardStore
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
                super.init()
                board.setString("这是一条用于界面验证的模拟文本。\n支持中文、多行和 Emoji 📝", forType: .string)
                return
            }
        }
        #endif
        store = ClipboardStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Unit tests use isolated pasteboards and must not capture the user's clipboard.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.stop()
        Task {
            await store.finishPendingSave()
            if store.storageError == .save {
                let alert = NSAlert()
                alert.messageText = "本机缓存尚未成功更新"
                alert.informativeText = "现在退出可能丢失最新记录或保留旧缓存。可以返回后重试。"
                alert.addButton(withTitle: "返回")
                alert.addButton(withTitle: "仍然退出")
                if alert.runModal() == .alertFirstButtonReturn {
                    store.start()
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
