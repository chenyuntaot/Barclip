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
}

@MainActor
private final class PersistencePasteboard: PasteboardAccess {
    var changeCount = 0
    var isAccessDenied = false
    var containsText = true
    var text: String?
    func publish(_ value: String) { text = value; changeCount += 1 }
    func readText() -> String? { text }
    func writeText(_ text: String) -> Bool { publish(text); return true }
}
