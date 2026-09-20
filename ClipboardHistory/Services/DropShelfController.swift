import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DropShelfState {
    var isTargeted = false
    var isExpanded = false
}

@MainActor
final class DropShelfController {
    let panel: NSPanel
    private let store: FileStagingStore
    private let monitor: DragSessionMonitor
    private let state = DropShelfState()
    private var hideWork: DispatchWorkItem?
    private var didPrepare = false

    init(store: FileStagingStore, pasteboard: any DragPasteboardAccess = SystemDragPasteboard()) {
        self.store = store
        self.monitor = DragSessionMonitor(pasteboard: pasteboard)
        panel = Self.makePanel()
        let host = ClearHostingView(rootView: DropShelfRoot(state: state) { [weak self] urls in
            self?.store.stage(urls)
            self?.hide()
        })
        host.frame = NSRect(origin: .zero, size: MenuBarDropAnchor.shelfSize)
        panel.contentView = host
        monitor.isInternalDrag = { [weak store] in store?.isExporting == true }
        monitor.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        prepareIfNeeded()
        monitor.start()
    }

    func stop() {
        hideWork?.cancel()
        hideWork = nil
        monitor.stop()
        store.endExport()
        panel.orderOut(nil)
    }

    func show() {
        prepareIfNeeded()
        hideWork?.cancel()
        hideWork = nil
        let placement = MenuBarDropAnchor.currentPlacement(excluding: [panel.windowNumber])
        state.isExpanded = false
        panel.setFrame(placement.frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        Task { @MainActor in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                self.state.isExpanded = true
            }
        }
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        state.isTargeted = false
        state.isExpanded = false
        store.endExport()
        panel.orderOut(nil)
    }

    private func handle(_ event: DragSessionEvent) {
        switch event {
        case .began:
            show()
        case .ended:
            store.endExport()
            scheduleHide(after: state.isTargeted ? 0.4 : 0.08)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func prepareIfNeeded() {
        guard !didPrepare else { return }
        didPrepare = true
        panel.setFrame(NSRect(origin: .zero, size: MenuBarDropAnchor.shelfSize), display: false)
        panel.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: MenuBarDropAnchor.shelfSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .none
        return panel
    }
}

@MainActor
private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
    }
}

private struct DropShelfRoot: View {
    @Bindable var state: DropShelfState
    var onDrop: ([URL]) -> Void

    var body: some View {
        DropShelfView(
            isTargeted: $state.isTargeted,
            isExpanded: state.isExpanded,
            onDrop: onDrop
        )
        .background(.clear)
        .modifier(ClearWindowBackground())
    }
}

private struct ClearWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}
