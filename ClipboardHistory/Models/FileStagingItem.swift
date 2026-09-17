import Foundation

struct FileStagingItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var bookmark: Data
    var displayName: String
    var resourceIdentifier: String
    var byteSize: Int64
    var isDirectory: Bool
    var addedAt: Date
    var resolvedURL: URL?
    var isMissing: Bool

    static func make(from url: URL, id: UUID = UUID(), addedAt: Date = Date()) throws -> FileStagingItem {
        let fileURL = url.standardizedFileURL
        guard fileURL.isFileURL else { throw FileStagingError.unavailable }
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            throw FileStagingError.unavailable
        }
        let values = try fileURL.resourceValues(forKeys: [.nameKey, .fileSizeKey, .isDirectoryKey, .isPackageKey])
        return FileStagingItem(
            id: id,
            bookmark: try bookmarkData(from: fileURL),
            displayName: values.name ?? fileURL.lastPathComponent,
            resourceIdentifier: Self.resourceIdentifier(for: fileURL),
            byteSize: Int64(values.fileSize ?? 0),
            isDirectory: isDirectory.boolValue && values.isPackage != true,
            addedAt: addedAt,
            resolvedURL: fileURL,
            isMissing: false
        )
    }

    func refreshingResolution() -> FileStagingItem {
        var copy = self
        guard let url = resolvingBookmarkURL() else {
            copy.resolvedURL = nil
            copy.isMissing = true
            return copy
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            copy.resolvedURL = nil
            copy.isMissing = true
            return copy
        }
        copy.resolvedURL = url
        copy.isMissing = false
        copy.isDirectory = isDirectory.boolValue && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true)
        if let name = try? url.resourceValues(forKeys: [.nameKey]).name {
            copy.displayName = name
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            copy.byteSize = Int64(size)
        }
        if let refreshed = try? Self.bookmarkData(from: url) {
            copy.bookmark = refreshed
            copy.resourceIdentifier = Self.resourceIdentifier(for: url)
        }
        return copy
    }

    func resolvingBookmarkURL() -> URL? {
        var isStale = false
        let scoped = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if let scoped {
            return scoped.standardizedFileURL
        }
        let plain = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return plain?.standardizedFileURL
    }

    static func bookmarkData(from url: URL) throws -> Data {
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resourceIdentifier(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .fileResourceIdentifierKey])
        if let volume = values?.volumeUUIDString, let fileID = values?.fileResourceIdentifier {
            return "\(volume)-\(fileID)"
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

enum FileStagingError: Error {
    case unavailable
    case copyFailed
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case text
    case image
    case files

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .files: "文件"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .image: "photo"
        case .files: "tray"
        }
    }

    var clipboardKind: ClipboardKind? {
        switch self {
        case .text: .text
        case .image: .image
        case .files: nil
        }
    }
}
