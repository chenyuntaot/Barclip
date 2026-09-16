import Foundation

actor HistoryRepository {
    private let fileURL: URL
    private var latestRevision = -1

    init(fileURL: URL = URL.applicationSupportDirectory
        .appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        .appending(path: "history.json")) {
        self.fileURL = fileURL
    }

    func load() throws -> [ClipboardEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: fileURL))
    }

    func save(_ entries: [ClipboardEntry]?, revision: Int) throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        guard let entries, !entries.isEmpty else {
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
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
