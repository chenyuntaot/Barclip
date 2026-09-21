import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ClipboardStore {
    static let capacityRange = 1...200
    static let defaultCapacity = 50
    static let maxImageBytes = 30 * 1_048_576
    private(set) var entries: [ClipboardEntry] = []
    private(set) var imageEntries: [ClipboardEntry] = []
    private(set) var textCapacity: Int
    private(set) var imageCapacity: Int
    private(set) var retention: RetentionPolicy
    private(set) var message: StatusMessage?
    private(set) var accessDenied = false
    private(set) var isLoading = false
    private(set) var storageError: StorageError?

    enum StatusMessage: Equatable, Sendable {
        case pasteboardReadFailed
        case skippedOversizedText
        case skippedOversizedImage
        case copyFailed
        case copied

        var text: String {
            switch self {
            case .pasteboardReadFailed:
                String(localized: "无法读取剪贴板，请检查系统的剪贴板访问设置后重试。")
            case .skippedOversizedText:
                String(localized: "已跳过超过 1 MB 的文本。")
            case .skippedOversizedImage:
                String(localized: "已跳过超过 30 MB 的图片。")
            case .copyFailed:
                String(localized: "复制失败，请重试。")
            case .copied:
                String(localized: "已复制，可使用 ⌘V 粘贴。")
            }
        }

        var allowsRetry: Bool {
            self == .pasteboardReadFailed
        }
    }

    enum StorageError {
        case load, save

        var message: String {
            switch self {
            case .load:
                String(localized: "无法读取本机历史，已暂停记录。请重试，或清空历史后继续。")
            case .save:
                String(localized: "本机缓存更新失败，退出后可能丢失记录或保留旧缓存。请重试。")
            }
        }
    }

    @ObservationIgnored private let pasteboard: any PasteboardAccess
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: HistoryRepository
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var didRestore = false
    private static let logger = Logger(subsystem: "local.ClipboardHistory", category: "Clipboard")

    init(
        pasteboard: any PasteboardAccess = PasteboardService(),
        defaults: UserDefaults = .standard,
        repository: HistoryRepository = HistoryRepository()
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.repository = repository
        retention = RetentionPolicy(rawValue: defaults.string(forKey: "retentionPolicy") ?? "") ?? .session
        let legacyCapacity = Self.savedCapacity(in: defaults, forKey: "historyCapacity")
        textCapacity = Self.savedCapacity(in: defaults, forKey: "textHistoryCapacity")
            ?? legacyCapacity
            ?? Self.defaultCapacity
        imageCapacity = Self.savedCapacity(in: defaults, forKey: "imageHistoryCapacity")
            ?? legacyCapacity
            ?? Self.defaultCapacity
        lastChangeCount = pasteboard.changeCount
    }

    deinit { monitor?.cancel() }

    func entries(for kind: ClipboardKind) -> [ClipboardEntry] {
        switch kind {
        case .text: entries
        case .image: imageEntries
        }
    }

    func capacity(for kind: ClipboardKind) -> Int {
        switch kind {
        case .text: textCapacity
        case .image: imageCapacity
        }
    }

    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            if self?.didRestore == false { await self?.restore() }
            while !Task.isCancelled {
                self?.poll()
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    // Sleep throws on cancellation when monitoring stops.
                    return
                }
            }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    func poll() {
        guard !isLoading, storageError != .load else { return }
        let wasDenied = accessDenied
        accessDenied = pasteboard.isAccessDenied
        guard !accessDenied else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount || wasDenied else { return }
        lastChangeCount = count
        if pasteboard.containsImage {
            guard let png = pasteboard.readPNG() else {
                message = .pasteboardReadFailed
                Self.logger.error("Pasteboard image read failed")
                return
            }
            guard pasteboard.changeCount == count else { return }
            recordImage(png)
            return
        }
        guard pasteboard.containsText else { return }
        guard let text = pasteboard.readText() else {
            message = .pasteboardReadFailed
            Self.logger.error("Pasteboard text read failed")
            return
        }
        guard pasteboard.changeCount == count else { return }
        record(text)
    }

    func retry() {
        lastChangeCount = pasteboard.changeCount - 1
        message = nil
        poll()
    }

    private func record(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard text.utf8.count <= 1_048_576 else {
            message = .skippedOversizedText
            return
        }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text), at: 0)
        entries = Array(entries.prefix(textCapacity))
        message = nil
        persist()
    }

    private func recordImage(_ data: Data) {
        guard !data.isEmpty else { return }
        guard data.count <= Self.maxImageBytes else {
            message = .skippedOversizedImage
            return
        }
        imageEntries.removeAll { $0.imagePNG == data }
        imageEntries.insert(ClipboardEntry(imagePNG: data), at: 0)
        imageEntries = Array(imageEntries.prefix(imageCapacity))
        message = nil
        persist()
    }

    func setCapacity(_ value: Int, for kind: ClipboardKind) {
        guard !isLoading, storageError != .load, Self.capacityRange.contains(value) else { return }
        switch kind {
        case .text:
            textCapacity = value
            defaults.set(value, forKey: "textHistoryCapacity")
            entries = Array(entries.prefix(value))
        case .image:
            imageCapacity = value
            defaults.set(value, forKey: "imageHistoryCapacity")
            imageEntries = Array(imageEntries.prefix(value))
        }
        persist()
    }

    func setRetention(_ value: RetentionPolicy) {
        guard !isLoading, storageError != .load else { return }
        retention = value
        defaults.set(value.rawValue, forKey: "retentionPolicy")
        persist()
    }

    func clear(_ kind: ClipboardKind? = nil) {
        guard !isLoading else { return }
        switch kind {
        case .text: entries.removeAll()
        case .image: imageEntries.removeAll()
        case nil:
            entries.removeAll()
            imageEntries.removeAll()
        }
        lastChangeCount = pasteboard.changeCount
        message = nil
        didRestore = true
        storageError = nil
        persist()
    }

    func copyCacheDirectoryPath() -> Bool {
        let succeeded = pasteboard.writeText(HistoryRepository.cacheDirectoryURL().path(percentEncoded: false))
        // Copying a settings value must not collect it as a new history entry.
        lastChangeCount = pasteboard.changeCount
        if !succeeded {
            Self.logger.error("Pasteboard cache directory write failed")
        }
        return succeeded
    }

    func copy(_ entry: ClipboardEntry) {
        switch entry.kind {
        case .text:
            guard pasteboard.writeText(entry.text) else {
                message = .copyFailed
                Self.logger.error("Pasteboard text write failed")
                return
            }
            lastChangeCount = pasteboard.changeCount
            record(entry.text)
        case .image:
            guard let png = entry.imagePNG, pasteboard.writePNG(png) else {
                message = .copyFailed
                Self.logger.error("Pasteboard image write failed")
                return
            }
            lastChangeCount = pasteboard.changeCount
            recordImage(png)
        }
        message = .copied
    }

    func restore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if retention == .persistent {
                let restored = try await repository.load()
                var seenText = Set<String>()
                var seenImage = Set<Data>()
                var texts: [ClipboardEntry] = []
                var images: [ClipboardEntry] = []
                for entry in restored {
                    switch entry.kind {
                    case .text:
                        guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              entry.text.utf8.count <= 1_048_576,
                              seenText.insert(entry.text).inserted else { continue }
                        texts.append(entry)
                    case .image:
                        guard let png = entry.imagePNG,
                              !png.isEmpty,
                              png.count <= Self.maxImageBytes,
                              seenImage.insert(png).inserted else { continue }
                        images.append(entry)
                    }
                }
                entries = Array(texts.prefix(textCapacity))
                imageEntries = Array(images.prefix(imageCapacity))
            } else {
                try await repository.save(nil, revision: revision)
            }
            didRestore = true
            storageError = nil
        } catch {
            storageError = .load
            Self.logger.error("Local history restoration failed")
        }
    }

    func retryStorage() async {
        if storageError == .load {
            await restore()
        } else {
            persist()
            await finishPendingSave()
        }
    }

    private func persist() {
        revision += 1
        let currentRevision = revision
        let snapshot = retention == .persistent ? entries + imageEntries : nil
        let repository = repository
        saveTask = Task { [weak self] in
            do {
                try await repository.save(snapshot, revision: currentRevision)
                guard let self, self.revision == currentRevision else { return }
                self.storageError = nil
            } catch {
                guard let self, self.revision == currentRevision else { return }
                self.storageError = .save
                Self.logger.error("Local history update failed")
            }
        }
    }

    func finishPendingSave() async {
        await saveTask?.value
    }

    func wipeDiskCache() async -> Bool {
        do {
            try await repository.wipeCacheDirectory()
            storageError = nil
            return true
        } catch {
            storageError = .save
            Self.logger.error("Disk cache wipe failed")
            return false
        }
    }

    private static func savedCapacity(in defaults: UserDefaults, forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.integer(forKey: key)
        return capacityRange.contains(value) ? value : nil
    }
}
