import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class HistoryPersistenceTests: XCTestCase {
    private var directory: URL = FileManager.default.temporaryDirectory
    private var suite = ""
    private var fileURL: URL { directory.appending(path: "history.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "HistoryPersistenceTests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func makeStore() throws -> (ClipboardStore, PersistencePasteboard) {
        let board = PersistencePasteboard()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (ClipboardStore(
            pasteboard: board,
            defaults: defaults,
            repository: HistoryRepository(fileURL: fileURL)
        ), board)
    }

    func testPersistentRestartAndClear() async throws {
        let (store, board) = try makeStore()
        await store.restore()
        store.setRetention(.persistent)
        board.publish("中文 📝\n  original whitespace  ")
        store.poll()
        await store.finishPendingSave()
        let (reopened, _) = try makeStore()
        await reopened.restore()
        XCTAssertEqual(reopened.retention, .persistent)
        XCTAssertEqual(reopened.entries, store.entries)
        reopened.clear()
        await reopened.finishPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        await reopened.restore()
        XCTAssertTrue(reopened.entries.isEmpty)
        XCTAssertEqual(board.text, "中文 📝\n  original whitespace  ")
    }

    func testSessionPolicyDeletesDiskButRetainsCurrentEntries() async throws {
        let (store, board) = try makeStore()
        store.setRetention(.persistent)
        board.publish("sample"); store.poll()
        await store.finishPendingSave()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        store.setRetention(.session)
        await store.finishPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(store.entries.first?.text, "sample")
        let (reopened, _) = try makeStore()
        await reopened.restore()
        XCTAssertEqual(reopened.retention, .session)
        XCTAssertTrue(reopened.entries.isEmpty)
    }

    func testCapacityPersistsTrimmedHistoryAndRapidClearWins() async throws {
        let (store, board) = try makeStore()
        store.setRetention(.persistent)
        for index in 0..<60 { board.publish("sample \(index)"); store.poll() }
        store.setCapacity(10)
        await store.finishPendingSave()
        let (reopened, _) = try makeStore()
        await reopened.restore()
        XCTAssertEqual(reopened.entries.count, 10)
        XCTAssertEqual(reopened.entries.first?.text, "sample 59")
        XCTAssertEqual(reopened.entries.last?.text, "sample 50")
        for index in 0..<20 { board.publish("rapid \(index)"); store.poll() }
        store.clear()
        await store.finishPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptCachePausesRecordingAndCanRetryOrClear() async throws {
        let (store, board) = try makeStore()
        store.setRetention(.persistent)
        await store.finishPendingSave()
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: fileURL)
        await store.restore()
        XCTAssertEqual(store.storageError, .load)
        board.publish("new text"); store.poll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
        await store.retryStorage()
        XCTAssertEqual(store.storageError, .load)
        store.clear()
        await store.finishPendingSave()
        XCTAssertNil(store.storageError)
        board.publish("recovered"); store.poll()
        await store.finishPendingSave()
        XCTAssertEqual(store.entries.first?.text, "recovered")
    }

    func testSaveFailureIsVisibleAndRetryRecovers() async throws {
        let parent = directory.appending(path: "blocked")
        try Data("not a directory".utf8).write(to: parent)
        let store = ClipboardStore(
            pasteboard: PersistencePasteboard(),
            defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
            repository: HistoryRepository(fileURL: parent.appending(path: "history.json"))
        )
        store.setRetention(.persistent)
        store.copy(ClipboardEntry(text: "sample"))
        await store.finishPendingSave()
        XCTAssertEqual(store.storageError, .save)
        try FileManager.default.removeItem(at: parent)
        await store.retryStorage()
        XCTAssertNil(store.storageError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.appending(path: "history.json").path))
    }

    func testRepositoryRejectsStaleWritesAfterDeletion() async throws {
        let repository = HistoryRepository(fileURL: fileURL)
        try await repository.save([ClipboardEntry(text: "sample")], revision: 2)
        try await repository.save(nil, revision: 4)
        try await repository.save([ClipboardEntry(text: "stale")], revision: 3)
        let restored = try await repository.load()
        XCTAssertTrue(restored.isEmpty)
    }

    func testHistoryURLUsesBarclipApplicationSupport() {
        let support = directory.appending(path: "Application Support")
        XCTAssertEqual(
            HistoryRepository.historyURL(inApplicationSupport: support),
            support.appending(path: "Barclip/history.json")
        )
        XCTAssertEqual(
            HistoryRepository.historyURL(),
            URL.applicationSupportDirectory.appending(path: "Barclip/history.json")
        )
    }

    func testDeletingAppBundlePreservesMigratedTextAndImages() async throws {
        let app = directory.appending(path: "Barclip.app")
        let legacy = app.appending(path: "Contents/Library/Application Support")
        let oldFile = legacy.appending(path: "history.json")
        let entries = [ClipboardEntry(text: "old text"), ClipboardEntry(imagePNG: TestPNG.pixel)]
        try await HistoryRepository(fileURL: oldFile).save(entries, revision: 1)
        let original = try Data(contentsOf: oldFile)
        let repository = HistoryRepository(fileURL: fileURL, legacyDirectories: [legacy])
        let migrated = try await repository.load()
        XCTAssertEqual(migrated, entries)
        XCTAssertEqual(try Data(contentsOf: oldFile), original)
        try FileManager.default.removeItem(at: app)
        let restored = try await HistoryRepository(fileURL: fileURL).load()
        XCTAssertEqual(restored, entries)
    }

    func testLegacyApplicationSupportIsCopiedWithoutDeletingSource() async throws {
        let legacy = directory.appending(path: "ClipboardHistory")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let oldFile = legacy.appending(path: "history.json")
        try JSONEncoder().encode([ClipboardEntry(text: "old cache")]).write(to: oldFile)
        let repository = HistoryRepository(fileURL: fileURL, legacyDirectories: [legacy])
        let restored = try await repository.load()
        XCTAssertEqual(restored.map(\.text), ["old cache"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFile.path))
    }

    func testClearPreventsLegacyReimportAfterRestart() async throws {
        let legacy = directory.appending(path: "legacy")
        try await HistoryRepository(fileURL: legacy.appending(path: "history.json"))
            .save([ClipboardEntry(text: "old")], revision: 1)
        let repository = HistoryRepository(fileURL: fileURL, legacyDirectories: [legacy])
        try await repository.save(nil, revision: 1)
        let restored = try await HistoryRepository(fileURL: fileURL, legacyDirectories: [legacy]).load()
        XCTAssertTrue(restored.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appending(path: "history.json").path))
    }

    func testNewHistoryWinsOverBothLegacyLocations() async throws {
        let sources = [directory.appending(path: "bundle"), directory.appending(path: "old-support")]
        for source in sources {
            try await HistoryRepository(fileURL: source.appending(path: "history.json"))
                .save([ClipboardEntry(text: source.lastPathComponent)], revision: 1)
        }
        let repository = HistoryRepository(fileURL: fileURL, legacyDirectories: sources)
        let migrated = try await repository.load()
        XCTAssertEqual(migrated.map(\.text), ["bundle"])
        try await repository.save([ClipboardEntry(text: "new")], revision: 1)
        let restored = try await HistoryRepository(fileURL: fileURL, legacyDirectories: sources).load()
        XCTAssertEqual(restored.map(\.text), ["new"])
        try await repository.save(nil, revision: 2)
        let cleared = try await HistoryRepository(fileURL: fileURL, legacyDirectories: sources).load()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testCorruptLegacyCacheCanRetryWithoutLosingSource() async throws {
        let legacy = directory.appending(path: "legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let oldFile = legacy.appending(path: "history.json")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: oldFile)
        let repository = HistoryRepository(fileURL: fileURL, legacyDirectories: [legacy])
        do {
            _ = try await repository.load()
            XCTFail("Corrupt migration must fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: oldFile), corrupt)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }
        try JSONEncoder().encode([ClipboardEntry(text: "repaired")]).write(to: oldFile)
        let restored = try await repository.load()
        XCTAssertEqual(restored.map(\.text), ["repaired"])
    }

    func testMigrationWriteFailureCanRetryWithoutChangingSource() async throws {
        let legacy = directory.appending(path: "legacy")
        let oldFile = legacy.appending(path: "history.json")
        try await HistoryRepository(fileURL: oldFile).save([ClipboardEntry(imagePNG: TestPNG.pixel)], revision: 1)
        let original = try Data(contentsOf: oldFile)
        let blocked = directory.appending(path: "blocked")
        try Data("file".utf8).write(to: blocked)
        let target = blocked.appending(path: "history.json")
        let repository = HistoryRepository(fileURL: target, legacyDirectories: [legacy])
        do {
            _ = try await repository.load()
            XCTFail("Migration to an unwritable directory must fail")
        } catch {
            XCTAssertEqual(try Data(contentsOf: oldFile), original)
        }
        try FileManager.default.removeItem(at: blocked)
        let restored = try await repository.load()
        XCTAssertEqual(restored.first?.imagePNG, TestPNG.pixel)
    }

    func testPersistentImageUsesSidecarAndSurvivesRestart() async throws {
        let (store, board) = try makeStore()
        store.setRetention(.persistent)
        board.publishImage(TestPNG.pixel)
        store.poll()
        await store.finishPendingSave()
        let images = directory.appending(path: "images")
        let files = try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.pathExtension, "png")
        let (reopened, _) = try makeStore()
        await reopened.restore()
        XCTAssertEqual(reopened.imageEntries.first?.imagePNG, TestPNG.pixel)
        XCTAssertTrue(reopened.entries.isEmpty)
        reopened.clear(.image)
        await reopened.finishPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMissingImageSidecarSkipsEntryWithoutFailingLoad() async throws {
        let repository = HistoryRepository(fileURL: fileURL)
        try await repository.save([
            ClipboardEntry(text: "keep"),
            ClipboardEntry(imagePNG: TestPNG.pixel)
        ], revision: 1)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory.appending(path: "images"),
            includingPropertiesForKeys: nil
        )
        try FileManager.default.removeItem(at: files[0])
        let restored = try await repository.load()
        XCTAssertEqual(restored.map(\.text), ["keep"])
        XCTAssertTrue(restored.allSatisfy { $0.kind == .text })
    }
}

@MainActor
private final class PersistencePasteboard: PasteboardAccess {
    var changeCount = 0
    var isAccessDenied = false
    var containsText = true
    var containsImage = false
    var text: String?
    var png: Data?
    func publish(_ value: String) {
        text = value
        png = nil
        containsText = true
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
    func readText() -> String? { text }
    func readPNG() -> Data? { png }
    func writeText(_ text: String) -> Bool { publish(text); return true }
    func writePNG(_ data: Data) -> Bool { publishImage(data); return true }
}
