import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class FileStagingTests: XCTestCase {
    private var directory: URL = FileManager.default.temporaryDirectory
    private var suite = ""
    private var stagingURL: URL { directory.appending(path: "file-staging.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "FileStagingTests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private func makeStore(persistent: Bool = false) throws -> FileStagingStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(
            (persistent ? RetentionPolicy.persistent : RetentionPolicy.session).rawValue,
            forKey: "retentionPolicy"
        )
        return FileStagingStore(
            defaults: defaults,
            repository: FileStagingRepository(fileURL: stagingURL)
        )
    }

    private func makeFile(name: String, contents: Data = Data("hello".utf8)) throws -> URL {
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url
    }

    func testStageKeepsOriginalAndRecordsBookmarkOnly() async throws {
        let payload = Data(repeating: 7, count: 120_000)
        let url = try makeFile(name: "note.txt", contents: payload)
        let store = try makeStore(persistent: true)
        store.stage([url])
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.displayName, "note.txt")
        XCTAssertEqual(try Data(contentsOf: url), payload)
        await store.finishPendingSave()
        let json = try Data(contentsOf: stagingURL)
        XCTAssertLessThan(json.count, 8_192)
        XCTAssertFalse(json.contains(payload.prefix(32)))
    }

    func testRestagingSameFileMovesToTop() throws {
        let first = try makeFile(name: "a.txt")
        let second = try makeFile(name: "b.txt")
        let store = try makeStore()
        store.stage([first, second])
        XCTAssertEqual(store.items.map(\.displayName), ["a.txt", "b.txt"])
        store.stage([first])
        XCTAssertEqual(store.items.map(\.displayName), ["a.txt", "b.txt"])
        XCTAssertEqual(store.items.count, 2)
    }

    func testMissingOriginalIsMarkedWithoutRemovingReference() throws {
        let url = try makeFile(name: "gone.txt")
        let store = try makeStore()
        store.stage([url])
        try FileManager.default.removeItem(at: url)
        store.refresh()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].isMissing)
        XCTAssertNil(store.items[0].resolvedURL)
        XCTAssertNil(store.resolvedURL(for: store.items[0]))
    }

    func testExportCopyLeavesSourceAndDuplicatesBytes() throws {
        let source = try makeFile(name: "source.txt", contents: Data("copied".utf8))
        let destination = directory.appending(path: "out").appending(path: "source.txt")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileStagingTransfer.copyItem(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: source), Data("copied".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("copied".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testFolderExportCopiesTreeAndLeavesSource() throws {
        let folder = directory.appending(path: "Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("pic".utf8).write(to: folder.appending(path: "pic.txt"))
        let store = try makeStore()
        store.stage([folder])
        XCTAssertEqual(store.items.first?.isDirectory, true)
        let destination = directory.appending(path: "Album-copy")
        try FileStagingTransfer.copyItem(from: folder, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "pic.txt").path))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "pic.txt")), Data("pic".utf8))
    }

    func testCapacityTrimsOldestStagedFiles() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(10, forKey: "historyCapacity")
        let store = FileStagingStore(
            defaults: defaults,
            repository: FileStagingRepository(fileURL: stagingURL)
        )
        for index in 1...12 {
            store.stage([try makeFile(name: "file-\(index).txt")])
        }
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.items.first?.displayName, "file-12.txt")
        XCTAssertEqual(store.items.last?.displayName, "file-3.txt")
        store.setCapacity(10)
        store.setCapacity(26)
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(
            FileStagingStore(defaults: defaults, repository: FileStagingRepository(fileURL: stagingURL)).capacity,
            26
        )
        store.setCapacity(0)
        store.setCapacity(201)
        XCTAssertEqual(store.capacity, 26)
    }

    func testPersistentRestartAndSessionDoesNotWrite() async throws {
        let url = try makeFile(name: "keep.txt")
        let persistent = try makeStore(persistent: true)
        persistent.stage([url])
        await persistent.finishPendingSave()
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingURL.path))
        let restored = try makeStore(persistent: true)
        await restored.restore()
        XCTAssertEqual(restored.items.first?.displayName, "keep.txt")
        XCTAssertEqual(restored.items.first?.resolvedURL?.standardizedFileURL, url.standardizedFileURL)

        let session = try makeStore()
        session.stage([url])
        await session.finishPendingSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        session.clear()
        await session.finishPendingSave()
        XCTAssertTrue(session.items.isEmpty)
    }

    func testCorruptStagingFileIsKeptAndSurfaced() async throws {
        try Data("not-json".utf8).write(to: stagingURL)
        let store = try makeStore(persistent: true)
        await store.restore()
        XCTAssertEqual(store.storageError, .load)
        XCTAssertEqual(try Data(contentsOf: stagingURL), Data("not-json".utf8))
    }

    func testDropItemURLParsing() {
        let file = directory.appending(path: "drop.txt")
        XCTAssertEqual(FileStagingTransfer.url(fromDropItem: file), file)
        XCTAssertEqual(FileStagingTransfer.url(fromDropItem: file as NSURL), file)
        XCTAssertEqual(
            FileStagingTransfer.url(fromDropItem: Data(file.absoluteString.utf8))?.absoluteString,
            file.absoluteString
        )
        XCTAssertNil(FileStagingTransfer.url(fromDropItem: "https://example.com"))
    }

    func testItemProviderRoundTripLoadsFileURL() async throws {
        let url = try makeFile(name: "provider.txt")
        let provider = NSItemProvider(contentsOf: url)
        XCTAssertNotNil(provider)
        let loaded = await FileStagingTransfer.urls(from: [try XCTUnwrap(provider)])
        XCTAssertEqual(loaded.first?.standardizedFileURL, url.standardizedFileURL)
    }

    func testDragTrackerIgnoresClicksAndStaleFilePasteboard() {
        var tracker = DragSessionTracker()
        tracker.resetBaseline(3)
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 3, isDragging: false, isInternal: false))
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 3, isDragging: true, isInternal: false))
        XCTAssertNil(tracker.poll(hasFileURLs: false, changeCount: 4, isDragging: true, isInternal: false))
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 4, isDragging: false, isInternal: false))
        tracker.consumePasteboard(4)
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 4, isDragging: true, isInternal: false))
    }

    func testDragTrackerBeginsOnlyForFreshFileDrag() {
        var tracker = DragSessionTracker()
        tracker.resetBaseline(1)
        XCTAssertEqual(tracker.poll(hasFileURLs: true, changeCount: 2, isDragging: true, isInternal: false), .began)
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 2, isDragging: true, isInternal: false))
        XCTAssertEqual(tracker.poll(hasFileURLs: true, changeCount: 2, isDragging: false, isInternal: false), .ended)
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 2, isDragging: true, isInternal: false))
        XCTAssertEqual(tracker.poll(hasFileURLs: true, changeCount: 3, isDragging: true, isInternal: false), .began)
        XCTAssertEqual(tracker.poll(hasFileURLs: true, changeCount: 3, isDragging: true, isInternal: true), .ended)
        XCTAssertNil(tracker.poll(hasFileURLs: true, changeCount: 3, isDragging: true, isInternal: false))
    }

    func testShelfFramePrefersStatusItemAndConvertsWindowCoordinates() {
        let cocoa = MenuBarDropAnchor.cocoaRect(
            fromCGWindowRect: CGRect(x: 100, y: 0, width: 22, height: 22),
            primaryDisplayHeight: 900
        )
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 878, width: 22, height: 22))
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let status = CGRect(x: 1200, y: 878, width: 22, height: 22)
        XCTAssertEqual(
            MenuBarDropAnchor.statusItemFrames(windowRects: [status, CGRect(x: 0, y: 0, width: 800, height: 600)], screens: [screen]),
            [status]
        )
        let placement = MenuBarDropAnchor.shelfPlacement(
            mouseLocation: CGPoint(x: 1210, y: 890),
            screens: [screen],
            statusItemFrames: [status]
        )
        XCTAssertEqual(placement.frame.width, MenuBarDropAnchor.shelfSize.width)
        XCTAssertEqual(placement.frame.maxX, 1211 + MenuBarDropAnchor.shelfSize.width / 2, accuracy: 1)
        XCTAssertEqual(placement.frame.maxY, status.minY - 2, accuracy: 0.5)
    }

    func testShelfFallbackStaysNearTrailingMenuBarNotScreenCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = MenuBarDropAnchor.shelfPlacement(
            mouseLocation: CGPoint(x: 720, y: 890),
            screens: [screen],
            statusItemFrames: [],
            rememberedAnchor: nil
        )
        XCTAssertGreaterThan(placement.frame.midX, screen.midX + 200)
        XCTAssertEqual(placement.frame.maxY, screen.maxY - 24, accuracy: 0.5)
        let remembered = CGRect(x: 200, y: 878, width: 24, height: 22)
        let fromMemory = MenuBarDropAnchor.shelfPlacement(
            mouseLocation: CGPoint(x: 720, y: 890),
            screens: [screen],
            statusItemFrames: [],
            rememberedAnchor: remembered
        )
        XCTAssertEqual(fromMemory.frame.midX, remembered.midX, accuracy: 1)
        XCTAssertEqual(fromMemory.frame.maxY, remembered.minY - 2, accuracy: 0.5)
    }

    func testImageThumbnailAndPreviewReadDroppedImageFile() throws {
        let url = try makeFile(name: "pixel.png", contents: TestPNG.pixel)
        let item = try FileStagingItem.make(from: url)
        XCTAssertNotNil(FileThumbnail.imageThumbnail(at: url))
        XCTAssertNotNil(FileThumbnail.previewImage(at: url))
        XCTAssertGreaterThan(FileThumbnail.icon(for: item).size.width, 0)
        XCTAssertTrue(FileQuickLookController.shared.present(item: item))
        FileQuickLookController.shared.hide()
        XCTAssertFalse(FileQuickLookController.shared.isVisible)
    }

    func testClipboardImagePreviewOpensAndSpaceStyleToggleClosesIt() {
        let controller = FileQuickLookController.shared
        controller.hide()
        XCTAssertFalse(controller.present(imagePNG: Data(), id: UUID()))
        XCTAssertFalse(controller.isVisible)

        let imageID = UUID()
        XCTAssertTrue(controller.present(imagePNG: TestPNG.pixel, id: imageID))
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.present(imagePNG: TestPNG.pixel, id: imageID))
        XCTAssertFalse(controller.isVisible)
    }

    func testDropShelfPanelIsNonactivatingAndHiddenUntilShown() throws {
        let store = try makeStore()
        let controller = DropShelfController(store: store)
        XCTAssertTrue(controller.panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(controller.panel.isVisible)
        controller.show()
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertGreaterThan(controller.panel.frame.width, 0)
        controller.hide()
        XCTAssertFalse(controller.panel.isVisible)
        controller.stop()
    }

    func testClearStagingLeavesOriginalAndClipboardAlone() throws {
        let url = try makeFile(name: "stay.txt")
        let files = try makeStore()
        files.stage([url])
        files.clear()
        XCTAssertTrue(files.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
