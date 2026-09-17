import AppKit
import UniformTypeIdentifiers

enum DragSessionEvent: Equatable, Sendable {
    case began
    case ended
}

struct DragSessionTracker: Equatable, Sendable {
    private(set) var isActive = false
    private var seenChangeCount: Int?

    mutating func resetBaseline(_ changeCount: Int) {
        seenChangeCount = changeCount
        isActive = false
    }

    mutating func consumePasteboard(_ changeCount: Int) {
        guard !isActive else { return }
        seenChangeCount = changeCount
    }

    mutating func poll(
        hasFileURLs: Bool,
        changeCount: Int,
        isDragging: Bool,
        isInternal: Bool
    ) -> DragSessionEvent? {
        if isInternal {
            guard isActive else { return nil }
            isActive = false
            seenChangeCount = changeCount
            return .ended
        }
        let isFreshPasteboard = seenChangeCount != changeCount
        let shouldShow = hasFileURLs && isDragging && isFreshPasteboard
        if shouldShow, !isActive {
            isActive = true
            return .began
        }
        if isActive, !shouldShow {
            isActive = false
            seenChangeCount = changeCount
            return .ended
        }
        return nil
    }
}

@MainActor
protocol DragPasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var containsFileURLs: Bool { get }
}

final class SystemDragPasteboard: DragPasteboardAccess {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var containsFileURLs: Bool {
        pasteboard.availableType(from: [.fileURL]) != nil
            || pasteboard.availableType(from: [NSPasteboard.PasteboardType(UTType.fileURL.identifier)]) != nil
    }
}

@MainActor
final class DragSessionMonitor {
    static let dragThreshold: CGFloat = 4

    private var tracker = DragSessionTracker()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTask: Task<Void, Never>?
    private var mouseDownLocation: CGPoint?
    private let pasteboard: any DragPasteboardAccess
    var isInternalDrag: () -> Bool = { false }
    var onEvent: ((DragSessionEvent) -> Void)?

    init(pasteboard: any DragPasteboardAccess = SystemDragPasteboard()) {
        self.pasteboard = pasteboard
    }

    func start() {
        stop()
        tracker.resetBaseline(pasteboard.changeCount)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.endIfPointerReleased()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        pollTask?.cancel()
        pollTask = nil
        mouseDownLocation = nil
        tracker = DragSessionTracker()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
        case .leftMouseUp:
            mouseDownLocation = nil
            if tracker.isActive {
                emit(isDragging: false)
            } else {
                tracker.consumePasteboard(pasteboard.changeCount)
            }
        case .leftMouseDragged:
            emit(isDragging: hasMovedPastThreshold)
        default:
            break
        }
    }

    private var hasMovedPastThreshold: Bool {
        guard let start = mouseDownLocation else {
            return true
        }
        let location = NSEvent.mouseLocation
        let deltaX = location.x - start.x
        let deltaY = location.y - start.y
        return hypot(deltaX, deltaY) >= Self.dragThreshold
    }

    private func endIfPointerReleased() {
        guard tracker.isActive, NSEvent.pressedMouseButtons == 0 else { return }
        mouseDownLocation = nil
        emit(isDragging: false)
    }

    private func emit(isDragging: Bool) {
        if let event = tracker.poll(
            hasFileURLs: pasteboard.containsFileURLs,
            changeCount: pasteboard.changeCount,
            isDragging: isDragging,
            isInternal: isInternalDrag()
        ) {
            onEvent?(event)
        }
    }
}
