import AppKit
import UniformTypeIdentifiers

enum FileStagingTransfer {
    static func copyItem(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw FileStagingError.unavailable
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileStagingError.copyFailed
        }
    }

    static func itemProvider(for url: URL, isDirectory: Bool) -> NSItemProvider {
        let type = contentType(for: url, isDirectory: isDirectory)
        let provider = NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        provider.registerFileRepresentation(for: type, visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        return provider
    }

    static func draggingExport(for url: URL, isDirectory: Bool) -> (writer: NSPasteboardWriting, retain: AnyObject) {
        let delegate = FileStagingPromiseDelegate(source: url)
        let provider = NSFilePromiseProvider(
            fileType: contentType(for: url, isDirectory: isDirectory).identifier,
            delegate: delegate
        )
        return (provider, delegate)
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        await urls(from: ItemProviderBox(providers))
    }

    static func scheduleLoad(_ providers: [NSItemProvider], receive: @escaping @MainActor ([URL]) -> Void) {
        let box = ItemProviderBox(providers)
        Task {
            let urls = await urls(from: box)
            await receive(urls)
        }
    }

    private static func urls(from box: ItemProviderBox) async -> [URL] {
        var urls: [URL] = []
        for provider in box.providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await fileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func contentType(for url: URL, isDirectory: Bool) -> UTType {
        if isDirectory { return .folder }
        if let type = UTType(filenameExtension: url.pathExtension), type != .data {
            return type
        }
        return .data
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        if let url = await loadURLObject(from: provider) {
            return url
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                continuation.resume(returning: url(fromDropItem: item))
            }
        }
    }

    private static func loadURLObject(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: fileURL(object as? URL))
            }
        }
    }

    static func url(fromDropItem item: Any?) -> URL? {
        if let url = item as? URL { return fileURL(url) }
        if let url = item as? NSURL { return fileURL(url as URL) }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return fileURL(fromString: string)
        }
        if let string = item as? String {
            return fileURL(fromString: string)
        }
        return nil
    }

    private static func fileURL(fromString string: String) -> URL? {
        fileURL(URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func fileURL(_ url: URL?) -> URL? {
        guard let url, url.isFileURL else { return nil }
        return url
    }
}

private struct ItemProviderBox: @unchecked Sendable {
    let providers: [NSItemProvider]

    init(_ providers: [NSItemProvider]) {
        self.providers = providers
    }
}

private final class FileStagingPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let source: URL

    init(source: URL) {
        self.source = source
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        source.lastPathComponent
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        OperationQueue()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            try FileStagingTransfer.copyItem(from: source, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
