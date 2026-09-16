import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var suites: [String] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    private func fixture() throws -> (ClipboardStore, FakePasteboard, UserDefaults) {
        let suite = "ClipboardHistoryTests.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        temporaryDirectories.append(directory)
        let repository = HistoryRepository(fileURL: directory.appending(path: "history.json"))
        let board = FakePasteboard()
        return (ClipboardStore(pasteboard: board, defaults: defaults, repository: repository), board, defaults)
    }

    func testTextOrderingDeduplicationAndOriginalWhitespace() async throws {
        let (store, board, _) = try fixture()
        board.publish("  第一行\n第二行  "); store.poll()
        board.publish("另一个"); store.poll()
        board.publish("  第一行\n第二行  "); store.poll()
        XCTAssertEqual(store.entries.map(\.text), ["  第一行\n第二行  ", "另一个"])
        store.poll()
        XCTAssertEqual(store.entries.count, 2)
        await store.finishPendingSave()
    }

    func testCapacityTrimsImmediatelyAndPersists() async throws {
        let (store, board, defaults) = try fixture()
        for value in 0..<60 { board.publish("\(value)"); store.poll() }
        XCTAssertEqual(store.entries.count, 50)
        store.setCapacity(10)
        XCTAssertEqual(store.entries.map(\.text), (50..<60).reversed().map(String.init))
        XCTAssertEqual(ClipboardStore(pasteboard: board, defaults: defaults).capacity, 10)
        store.setCapacity(100)
        XCTAssertEqual(store.entries.count, 10)
        store.setCapacity(-1)
        XCTAssertEqual(store.capacity, 100)
        await store.finishPendingSave()
        defaults.removeObject(forKey: "historyCapacity")
    }

    func testClearDoesNotRestoreCurrentTextOrOverwritePasteboard() async throws {
        let (store, board, _) = try fixture()
        board.publish("test"); store.poll()
        store.clear(); store.clear(); store.poll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(board.text, "test")
        board.publish("test"); store.poll()
        XCTAssertEqual(store.entries.count, 1)
        await store.finishPendingSave()
    }

    func testNonTextEmptyAndOversizedContent() throws {
        let (store, board, _) = try fixture()
        board.publish(" \n\t"); store.poll()
        board.publish("image", isText: false); store.poll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.imageEntries.isEmpty)
        board.publish(String(repeating: "a", count: 1_048_577)); store.poll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.message)
        board.publishImage(Data(count: ClipboardStore.maxImageBytes + 1)); store.poll()
        XCTAssertTrue(store.imageEntries.isEmpty)
        XCTAssertEqual(store.message, "已跳过超过 30 MB 的图片。")
    }

    func testImageOrderingDeduplicationAndIndependenceFromText() async throws {
        let (store, board, _) = try fixture()
        let first = TestPNG.pixel
        let second = TestPNG.altPixel
        board.publish("hello"); store.poll()
        board.publishImage(first); store.poll()
        board.publishImage(second); store.poll()
        board.publishImage(first); store.poll()
        board.png = first
        board.text = "https://example.com"
        board.containsImage = true
        board.containsText = true
        board.changeCount += 1
        store.poll()
        XCTAssertEqual(store.imageEntries.map(\.imagePNG), [first, second])
        XCTAssertEqual(store.entries.map(\.text), ["hello"])
        store.poll()
        XCTAssertEqual(store.imageEntries.count, 2)
        store.clear(.image)
        XCTAssertTrue(store.imageEntries.isEmpty)
        XCTAssertEqual(store.entries.map(\.text), ["hello"])
        await store.finishPendingSave()
    }

    func testImageCapacityTrimsIndependently() async throws {
        let (store, board, _) = try fixture()
        board.publish("keep"); store.poll()
        for index in 0..<60 {
            board.publishImage(TestPNG.unique(index)); store.poll()
        }
        XCTAssertEqual(store.imageEntries.count, 50)
        XCTAssertEqual(store.entries.count, 1)
        store.setCapacity(10)
        XCTAssertEqual(store.imageEntries.count, 10)
        XCTAssertEqual(store.entries.count, 1)
        await store.finishPendingSave()
    }

    func testImageCopyAndFailure() async throws {
        let (store, board, _) = try fixture()
        board.publishImage(TestPNG.pixel); store.poll()
        let entry = try XCTUnwrap(store.imageEntries.first)
        board.publish("text"); store.poll()
        store.copy(entry); store.poll()
        XCTAssertEqual(board.png, TestPNG.pixel)
        XCTAssertEqual(store.imageEntries.map(\.imagePNG), [TestPNG.pixel])
        XCTAssertEqual(store.entries.map(\.text), ["text"])
        board.writeSucceeds = false
        store.copy(entry)
        XCTAssertEqual(store.message, "复制失败，请重试。")
        await store.finishPendingSave()
    }

    func testPermissionDenialAndReadFailureRecover() async throws {
        let (store, board, _) = try fixture()
        board.isAccessDenied = true
        board.publish("private"); store.poll()
        XCTAssertTrue(store.accessDenied)
        XCTAssertEqual(board.readCount, 0)
        board.isAccessDenied = false
        store.poll()
        XCTAssertEqual(store.entries.first?.text, "private")
        board.publish(nil); store.poll()
        XCTAssertNotNil(store.message)
        board.text = "retry"
        store.retry()
        XCTAssertEqual(store.entries.first?.text, "retry")
        XCTAssertNil(store.message)
        await store.finishPendingSave()
    }

    func testCopyAndFailure() async throws {
        let (store, board, _) = try fixture()
        board.publish("first"); store.poll()
        let entry = try XCTUnwrap(store.entries.first)
        board.publish("second"); store.poll()
        store.copy(entry); store.poll()
        XCTAssertEqual(board.text, "first")
        XCTAssertEqual(store.entries.map(\.text), ["first", "second"])
        board.writeSucceeds = false
        store.copy(entry)
        XCTAssertEqual(store.message, "复制失败，请重试。")
        await store.finishPendingSave()
    }

    func testNamedSystemPasteboardIntegration() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        XCTAssertTrue(service.writeText("模拟文本\n📝"))
        XCTAssertTrue(service.containsText)
        XCTAssertFalse(service.containsImage)
        XCTAssertEqual(service.readText(), "模拟文本\n📝")
        XCTAssertTrue(service.writePNG(TestPNG.pixel))
        XCTAssertTrue(service.containsImage)
        XCTAssertFalse(service.containsText)
        XCTAssertEqual(service.readPNG(), TestPNG.pixel)
        board.clearContents()
        board.setData(TestPNG.pixel, forType: .png)
        board.setString("https://example.com", forType: .string)
        XCTAssertTrue(service.containsImage)
        XCTAssertTrue(service.containsText)
        board.clearContents()
        board.setData(TestPNG.pixel, forType: .tiff)
        XCTAssertTrue(service.containsImage)
        XCTAssertNotNil(service.readPNG())
        board.clearContents()
        board.setData(Data(), forType: .png)
        XCTAssertFalse(service.containsText)
        board.clearContents()
        board.setString("sensitive", forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        XCTAssertFalse(service.containsText)
        XCTAssertFalse(service.containsImage)
        board.clearContents()
        board.setString("file:///example", forType: .string)
        board.setString("file:///example", forType: .fileURL)
        XCTAssertFalse(service.containsText)
        board.clearContents()
        board.setData(TestPNG.pixel, forType: .png)
        board.setString("file:///tmp/Screenshot.png", forType: .fileURL)
        XCTAssertTrue(service.containsImage)
        XCTAssertFalse(service.containsText)
        XCTAssertEqual(service.readPNG(), TestPNG.pixel)
        board.clearContents()
        board.setData(try XCTUnwrap(NSImage(data: TestPNG.pixel)?.tiffRepresentation), forType: .tiff)
        board.setString("file:///Users/me/Desktop/Screenshot.png", forType: .fileURL)
        XCTAssertTrue(service.containsImage)
        XCTAssertFalse(service.containsText)
        XCTAssertNotNil(service.readPNG())
        board.clearContents()
        board.setString("file:///tmp/document.pdf", forType: .fileURL)
        XCTAssertFalse(service.containsImage)
        XCTAssertFalse(service.containsText)
    }

    func testScreenshotBitmapWithFileURLIsRecorded() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let suite = "ClipboardHistoryTests.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        temporaryDirectories.append(directory)
        let store = ClipboardStore(
            pasteboard: PasteboardService(pasteboard: board),
            defaults: defaults,
            repository: HistoryRepository(fileURL: directory.appending(path: "history.json"))
        )
        board.clearContents()
        board.setData(try XCTUnwrap(NSImage(data: TestPNG.pixel)?.tiffRepresentation), forType: .tiff)
        board.setString("file:///Users/me/Desktop/Screenshot.png", forType: .fileURL)
        store.poll()
        XCTAssertEqual(store.imageEntries.count, 1)
        XCTAssertFalse(try XCTUnwrap(store.imageEntries.first?.imagePNG).isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        board.clearContents()
        board.setString("file:///tmp/document.pdf", forType: .fileURL)
        store.poll()
        XCTAssertEqual(store.imageEntries.count, 1)
    }

    func testMonitorStopsAndCanRestart() async throws {
        let (store, board, _) = try fixture()
        store.start(); store.start()
        board.publish("running")
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(store.entries.first?.text, "running")
        store.stop()
        board.publish("stopped")
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(store.entries.first?.text, "running")
        store.start()
        try await Task.sleep(for: .milliseconds(650))
        store.stop()
        XCTAssertEqual(store.entries.first?.text, "stopped")
        await store.finishPendingSave()
    }
}

@MainActor
private final class FakePasteboard: PasteboardAccess {
    var changeCount = 0
    var isAccessDenied = false
    var containsText = true
    var containsImage = false
    var text: String?
    var png: Data?
    var readCount = 0
    var writeSucceeds = true
    func publish(_ value: String?, isText: Bool = true) {
        text = value
        png = nil
        containsText = isText
        containsImage = false
        changeCount += 1
    }
    func publishImage(_ data: Data) {
        png = data
        text = nil
        containsText = false
        containsImage = true
        changeCount += 1
    }
    func readText() -> String? { readCount += 1; return text }
    func readPNG() -> Data? { png }
    func writeText(_ text: String) -> Bool {
        guard writeSucceeds else { return false }
        publish(text)
        return true
    }
    func writePNG(_ data: Data) -> Bool {
        guard writeSucceeds else { return false }
        publishImage(data)
        return true
    }
}

enum TestPNG {
    static let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    static let altPixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=")!

    static func unique(_ index: Int) -> Data {
        pixel + Data([UInt8(truncatingIfNeeded: index)])
    }
}
