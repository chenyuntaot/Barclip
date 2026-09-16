import Foundation

actor HistoryRepository {
    private let fileURL: URL
    private let legacyDirectories: [URL]
    private var latestRevision = -1

    static func historyURL(inApplicationSupport directory: URL = .applicationSupportDirectory) -> URL {
        directory.appending(path: "Barclip", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    init() {
        fileURL = Self.historyURL()
        legacyDirectories = [
            Bundle.main.bundleURL.appending(path: "Contents/Library/Application Support", directoryHint: .isDirectory),
            URL.applicationSupportDirectory.appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        ]
    }

    init(fileURL: URL, legacyDirectories: [URL] = []) {
        self.fileURL = fileURL
        self.legacyDirectories = legacyDirectories
    }

    func load() throws -> [ClipboardEntry] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let entries = try decode(from: fileURL)
            try markMigrationComplete()
            return entries
        }
        guard !FileManager.default.fileExists(atPath: migrationMarker.path) else { return [] }
        for directory in legacyDirectories {
            let source = directory.appending(path: "history.json")
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let entries = try decode(from: source)
            try write(entries)
            try markMigrationComplete()
            return entries
        }
        try markMigrationComplete()
        return []
    }

    func save(_ entries: [ClipboardEntry]?, revision: Int) throws {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        guard let entries, !entries.isEmpty else {
            // Record the decision before deleting history so a restart cannot reimport old data.
            try markMigrationComplete()
            try removeSnapshotFiles()
            return
        }
        try write(entries)
        try markMigrationComplete()
    }

    private var migrationMarker: URL {
        fileURL.deletingLastPathComponent().appending(path: ".migration-complete")
    }

    private func markMigrationComplete() throws {
        guard !FileManager.default.fileExists(atPath: migrationMarker.path) else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data().write(to: migrationMarker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: migrationMarker.path)
    }

    private var imagesDirectory: URL {
        fileURL.deletingLastPathComponent().appending(path: "images", directoryHint: .isDirectory)
    }

    private func decode(from url: URL) throws -> [ClipboardEntry] {
        let persisted = try JSONDecoder().decode([PersistableEntry].self, from: Data(contentsOf: url))
        return try materialize(persisted, imagesDirectory: url.deletingLastPathComponent().appending(path: "images"))
    }

    private func materialize(_ items: [PersistableEntry], imagesDirectory: URL) throws -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []
        entries.reserveCapacity(items.count)
        for item in items {
            if let fileName = item.imageFileName {
                let imageURL = imagesDirectory.appending(path: fileName)
                if !FileManager.default.fileExists(atPath: imageURL.path) { continue }
                let data = try Data(contentsOf: imageURL)
                if data.isEmpty { continue }
                entries.append(ClipboardEntry(id: item.id, text: "", imagePNG: data, copiedAt: item.copiedAt))
            } else {
                entries.append(ClipboardEntry(id: item.id, text: item.text, copiedAt: item.copiedAt))
            }
        }
        return entries
    }

    private func write(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let persistable = entries.map { entry -> PersistableEntry in
            let fileName = entry.imagePNG == nil ? nil : "\(entry.id.uuidString).png"
            return PersistableEntry(
                id: entry.id,
                text: entry.imagePNG == nil ? entry.text : "",
                imageFileName: fileName,
                copiedAt: entry.copiedAt
            )
        }
        try writeImages(entries)
        let data = try JSONEncoder().encode(persistable)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func writeImages(_ entries: [ClipboardEntry]) throws {
        let images = entries.compactMap { entry -> (String, Data)? in
            guard let png = entry.imagePNG, !png.isEmpty else { return nil }
            return ("\(entry.id.uuidString).png", png)
        }
        if images.isEmpty {
            if FileManager.default.fileExists(atPath: imagesDirectory.path) {
                try FileManager.default.removeItem(at: imagesDirectory)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let keep = Set(images.map(\.0))
        for (name, png) in images {
            let imageURL = imagesDirectory.appending(path: name)
            try png.write(to: imageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)
        }
        let existing = try FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil
        )
        for url in existing where !keep.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func removeSnapshotFiles() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try FileManager.default.removeItem(at: imagesDirectory)
        }
    }
}

private struct PersistableEntry: Codable {
    var id: UUID
    var text: String
    var imageFileName: String?
    var copiedAt: Date
}
