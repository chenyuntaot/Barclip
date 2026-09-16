import Foundation

actor HistoryRepository {
    private let fileURL: URL
    private let legacyDirectory: URL?
    private var latestRevision = -1

    static var legacyDirectoryURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "ClipboardHistory", directoryHint: .isDirectory)
    }

    static func historyURL(inAppBundle bundleURL: URL = Bundle.main.bundleURL) -> URL {
        bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    init() {
        fileURL = Self.historyURL()
        legacyDirectory = Self.legacyDirectoryURL
    }

    init(fileURL: URL, legacyDirectory: URL? = nil) {
        self.fileURL = fileURL
        self.legacyDirectory = legacyDirectory
    }

    func load() throws -> [ClipboardEntry] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let entries = try decode(from: fileURL)
            try removeLegacyIfNeeded()
            return entries
        }
        guard let legacyFile = legacyHistoryFile,
              FileManager.default.fileExists(atPath: legacyFile.path) else { return [] }
        let entries = try decode(from: legacyFile)
        try write(entries)
        try removeLegacyIfNeeded()
        return entries
    }

    func save(_ entries: [ClipboardEntry]?, revision: Int) throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        guard let entries, !entries.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try removeLegacyIfNeeded()
            return
        }
        try write(entries)
        try removeLegacyIfNeeded()
    }

    private var legacyHistoryFile: URL? {
        legacyDirectory?.appending(path: "history.json")
    }

    private func decode(from url: URL) throws -> [ClipboardEntry] {
        try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: url))
    }

    private func write(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func removeLegacyIfNeeded() throws {
        guard let legacyDirectory, FileManager.default.fileExists(atPath: legacyDirectory.path) else { return }
        try FileManager.default.removeItem(at: legacyDirectory)
    }
}
