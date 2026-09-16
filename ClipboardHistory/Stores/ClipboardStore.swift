import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ClipboardStore {
    static let capacityOptions = [10, 25, 50, 100, 200]
    static let maxImageBytes = 8_388_608
    private(set) var entries: [ClipboardEntry] = []
    private(set) var imageEntries: [ClipboardEntry] = []
    private(set) var capacity: Int
    private(set) var retention: RetentionPolicy
    private(set) var message: String?
    private(set) var accessDenied = false
    private(set) var isLoading = false
    private(set) var storageError: StorageError?

    enum StorageError {
        case load, save

        var message: String {
            switch self {
            case .load: "无法读取本机历史，已暂停记录。请重试，或清空历史后继续。"
            case .save: "本机缓存更新失败，退出后可能丢失记录或保留旧缓存。请重试。"
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
        let saved = defaults.integer(forKey: "historyCapacity")
        capacity = Self.capacityOptions.contains(saved) ? saved : 50
        lastChangeCount = pasteboard.changeCount
    }

    deinit { monitor?.cancel() }

    func entries(for kind: ClipboardKind) -> [ClipboardEntry] {
        switch kind {
        case .text: entries
        case .image: imageEntries
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
                message = "无法读取剪贴板，请检查系统的剪贴板访问设置后重试。"
                Self.logger.error("Pasteboard image read failed")
                return
            }
            guard pasteboard.changeCount == count else { return }
            recordImage(png)
            return
        }
        guard pasteboard.containsText else { return }
        guard let text = pasteboard.readText() else {
            message = "无法读取剪贴板，请检查系统的剪贴板访问设置后重试。"
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
            message = "已跳过超过 1 MB 的文本。"
            return
        }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text), at: 0)
        entries = Array(entries.prefix(capacity))
        message = nil
        persist()
    }

    private func recordImage(_ data: Data) {
        guard !data.isEmpty else { return }
        guard data.count <= Self.maxImageBytes else {
            message = "已跳过超过 8 MB 的图片。"
            return
        }
        imageEntries.removeAll { $0.imagePNG == data }
        imageEntries.insert(ClipboardEntry(imagePNG: data), at: 0)
        imageEntries = Array(imageEntries.prefix(capacity))
        message = nil
        persist()
    }

    func setCapacity(_ value: Int) {
        guard !isLoading, storageError != .load, Self.capacityOptions.contains(value) else { return }
        capacity = value
        defaults.set(value, forKey: "historyCapacity")
        entries = Array(entries.prefix(value))
        imageEntries = Array(imageEntries.prefix(value))
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

    func copy(_ entry: ClipboardEntry) {
        switch entry.kind {
        case .text:
            guard pasteboard.writeText(entry.text) else {
                message = "复制失败，请重试。"
                Self.logger.error("Pasteboard text write failed")
                return
            }
            lastChangeCount = pasteboard.changeCount
            record(entry.text)
        case .image:
            guard let png = entry.imagePNG, pasteboard.writePNG(png) else {
                message = "复制失败，请重试。"
                Self.logger.error("Pasteboard image write failed")
                return
            }
            lastChangeCount = pasteboard.changeCount
            recordImage(png)
        }
        message = "已复制，可使用 ⌘V 粘贴。"
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
                entries = Array(texts.prefix(capacity))
                imageEntries = Array(images.prefix(capacity))
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
}
