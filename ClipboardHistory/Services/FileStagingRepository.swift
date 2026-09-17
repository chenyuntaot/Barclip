import Foundation

actor FileStagingRepository {
    private let fileURL: URL
    private var latestRevision = -1

    static func stagingURL(inApplicationSupport directory: URL = .applicationSupportDirectory) -> URL {
        HistoryRepository.cacheDirectoryURL(inApplicationSupport: directory).appending(path: "file-staging.json")
    }

    init() {
        fileURL = Self.stagingURL()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> [FileStagingItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let persisted = try JSONDecoder().decode([PersistableStagingItem].self, from: Data(contentsOf: fileURL))
        return persisted.map(\.item)
    }

    func save(_ items: [FileStagingItem]?, revision: Int) throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        guard let items, !items.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(items.map(PersistableStagingItem.init))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

private struct PersistableStagingItem: Codable {
    var id: UUID
    var bookmark: Data
    var displayName: String
    var resourceIdentifier: String
    var byteSize: Int64
    var isDirectory: Bool
    var addedAt: Date

    init(_ item: FileStagingItem) {
        id = item.id
        bookmark = item.bookmark
        displayName = item.displayName
        resourceIdentifier = item.resourceIdentifier
        byteSize = item.byteSize
        isDirectory = item.isDirectory
        addedAt = item.addedAt
    }

    var item: FileStagingItem {
        FileStagingItem(
            id: id,
            bookmark: bookmark,
            displayName: displayName,
            resourceIdentifier: resourceIdentifier,
            byteSize: byteSize,
            isDirectory: isDirectory,
            addedAt: addedAt,
            resolvedURL: nil,
            isMissing: true
        )
    }
}
