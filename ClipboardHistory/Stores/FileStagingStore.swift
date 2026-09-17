import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class FileStagingStore {
    private(set) var items: [FileStagingItem] = []
    private(set) var capacity: Int
    private(set) var retention: RetentionPolicy
    private(set) var message: StatusMessage?
    private(set) var isLoading = false
    private(set) var storageError: StorageError?
    private(set) var isExporting = false

    enum StatusMessage: Equatable, Sendable {
        case missing
        case previewMissing

        var text: String {
            switch self {
            case .missing:
                String(localized: "无法打开该文件，它可能已被移动或删除。")
            case .previewMissing:
                String(localized: "无法预览该文件，它可能已被移动或删除。")
            }
        }
    }

    enum StorageError: Equatable {
        case load, save

        var message: String {
            switch self {
            case .load:
                String(localized: "无法读取文件暂存，请重试。")
            case .save:
                String(localized: "无法更新文件暂存。")
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: FileStagingRepository
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    private static let logger = Logger(subsystem: "local.ClipboardHistory", category: "FileStaging")

    init(
        defaults: UserDefaults = .standard,
        repository: FileStagingRepository = FileStagingRepository()
    ) {
        self.defaults = defaults
        self.repository = repository
        retention = RetentionPolicy(rawValue: defaults.string(forKey: "retentionPolicy") ?? "") ?? .session
        let saved = defaults.integer(forKey: "historyCapacity")
        capacity = ClipboardStore.capacityOptions.contains(saved) ? saved : 50
    }

    func start() {
        Task { await restore() }
    }

    func stage(_ urls: [URL]) {
        guard storageError != .load else { return }
        var staged: [FileStagingItem] = []
        var seen = Set<String>()
        for url in urls {
            do {
                let item = try FileStagingItem.make(from: url)
                guard seen.insert(item.resourceIdentifier).inserted else { continue }
                staged.append(item)
            } catch {
                Self.logger.error("Unable to stage dropped file")
            }
        }
        guard !staged.isEmpty else { return }
        let identifiers = Set(staged.map(\.resourceIdentifier))
        items.removeAll { identifiers.contains($0.resourceIdentifier) }
        items.insert(contentsOf: staged, at: 0)
        items = Array(items.prefix(capacity))
        message = nil
        persist()
    }

    func remove(_ item: FileStagingItem) {
        items.removeAll { $0.id == item.id }
        if message != nil { message = nil }
        persist()
    }

    func clear() {
        guard !isLoading else { return }
        items.removeAll()
        message = nil
        storageError = nil
        persist()
    }

    func setCapacity(_ value: Int) {
        guard !isLoading, storageError != .load, ClipboardStore.capacityOptions.contains(value) else { return }
        capacity = value
        items = Array(items.prefix(value))
        persist()
    }

    func setRetention(_ value: RetentionPolicy) {
        guard !isLoading, storageError != .load else { return }
        retention = value
        persist()
    }

    func refresh() {
        items = items.map { $0.refreshingResolution() }
    }

    func resolvedURL(for item: FileStagingItem) -> URL? {
        let refreshed = item.refreshingResolution()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = refreshed
        }
        return refreshed.isMissing ? nil : refreshed.resolvedURL
    }

    func reportUnavailable(preview: Bool) {
        message = preview ? .previewMissing : .missing
    }

    func beginExport() {
        isExporting = true
    }

    func endExport() {
        isExporting = false
    }

    func restore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if retention == .persistent {
                let loaded = try await repository.load()
                items = Array(loaded.prefix(capacity)).map { $0.refreshingResolution() }
            } else {
                try await repository.save(nil, revision: revision)
            }
            storageError = nil
        } catch {
            storageError = .load
            Self.logger.error("Local file staging restoration failed")
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

    func finishPendingSave() async {
        await saveTask?.value
    }

    private func persist() {
        revision += 1
        let currentRevision = revision
        let snapshot = retention == .persistent ? items : nil
        let repository = repository
        saveTask = Task { [weak self] in
            do {
                try await repository.save(snapshot, revision: currentRevision)
                guard let self, self.revision == currentRevision else { return }
                self.storageError = nil
            } catch {
                guard let self, self.revision == currentRevision else { return }
                self.storageError = .save
                Self.logger.error("Local file staging update failed")
            }
        }
    }
}
