import AppKit
import SwiftUI

struct FileStagingView: View {
    @Environment(FileStagingStore.self) private var files
    @State private var selectedID: FileStagingItem.ID?
    @State private var isDropTargeted = false
    @State private var keyMonitor: Any?
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if let error = files.storageError {
                Text(error.message).font(.caption).foregroundStyle(.red)
                Button("重试缓存操作") {
                    Task { await files.retryStorage() }
                }
                .disabled(files.isLoading)
            }
            if let message = files.message {
                Text(message.text).font(.caption).foregroundStyle(.secondary)
            }
            if files.isLoading {
                ProgressView("正在读取历史…").frame(maxWidth: .infinity).frame(height: 220)
            } else if files.items.isEmpty {
                emptyState
            } else {
                grid
            }
            Text("暂存区只记录文件引用。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            receive(providers)
        }
        .onAppear {
            files.refresh()
            MenuBarDropAnchor.rememberOpenExtra()
            installKeyMonitor()
            gridFocused = true
        }
        .onDisappear { removeKeyMonitor() }
    }

    private var header: some View {
        HStack {
            Label {
                Text("Barclip")
            } icon: {
                ClipboardGlyph(pointSize: 16)
            }
            .font(.headline)
            .labelStyle(.titleAndIcon)
            Spacer()
            Text("\(files.items.count) / \(files.capacity)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("暂无暂存文件").font(.headline)
            Text("从访达或桌面把文件拖到这里。原位置会保留一份。")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(files.items) { item in
                    FileStagingCell(
                        item: item,
                        isSelected: selectedID == item.id,
                        onSelect: { selectedID = item.id },
                        onOpen: { open(item) },
                        onPreview: { preview(item) },
                        onRemove: { files.remove(item) },
                        onExportBegan: { files.beginExport() },
                        onExportEnded: { files.endExport() }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 180, idealHeight: 280, maxHeight: 320)
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            previewSelected()
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }

    private var selectedItem: FileStagingItem? {
        files.items.first { $0.id == selectedID } ?? files.items.first
    }

    private func receive(_ providers: [NSItemProvider]) -> Bool {
        FileStagingTransfer.scheduleLoad(providers) { urls in
            if !urls.isEmpty { files.stage(urls) }
        }
        return true
    }

    private func openSelected() {
        if let item = selectedItem { open(item) }
    }

    private func previewSelected() {
        if let item = selectedItem { preview(item) }
    }

    private func open(_ item: FileStagingItem) {
        selectedID = item.id
        guard let url = files.resolvedURL(for: item) else {
            files.reportUnavailable(preview: false)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func preview(_ item: FileStagingItem) {
        selectedID = item.id
        let current = files.items.first { $0.id == item.id } ?? item
        if current.isMissing || !FileQuickLookController.shared.present(item: current) {
            files.reportUnavailable(preview: true)
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            if event.charactersIgnoringModifiers == " " {
                previewSelected()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                openSelected()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private struct FileStagingCell: View {
    let item: FileStagingItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onRemove: () -> Void
    let onExportBegan: () -> Void
    let onExportEnded: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            FileThumbnailView(item: item)
                .frame(width: 72, height: 72)
                .padding(8)
                .modifier(RailGlassEffect(isActive: isSelected, cornerRadius: 12))
            Text(item.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .strikethrough(item.isMissing)
                .foregroundStyle(nameColor)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(item.isMissing ? Color.red : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .overlay {
            FileInteractionView(
                onSelect: onSelect,
                onOpen: onOpen,
                onPreview: onPreview,
                onRemove: onRemove,
                onExportBegan: onExportBegan,
                onExportEnded: onExportEnded,
                dragURL: item.isMissing ? nil : (item.resolvedURL ?? item.resolvingBookmarkURL()),
                isDirectory: item.isDirectory
            )
        }
        .contextMenu {
            Button("预览", action: onPreview)
                .disabled(item.isMissing)
            Button("在默认应用中打开", action: onOpen)
                .disabled(item.isMissing)
            Button("从暂存移除", action: onRemove)
        }
        .help("单击选中，空格预览，双击打开。向外拖时复制一份，不移动原文件。")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "预览", onPreview)
        .accessibilityAction(named: "在默认应用中打开", onOpen)
    }

    private var nameColor: Color {
        if item.isMissing { return .secondary }
        return isSelected ? .accentColor : .primary
    }

    private var subtitle: String {
        if item.isMissing { return String(localized: "文件已丢失") }
        if item.isDirectory { return String(localized: "文件夹") }
        return ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
    }
}

private struct FileThumbnailView: View {
    let item: FileStagingItem
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? FileThumbnail.icon(for: item))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: item.id) {
            image = FileThumbnail.icon(for: item)
        }
    }
}

private struct FileInteractionView: NSViewRepresentable {
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onPreview: () -> Void
    var onRemove: () -> Void
    var onExportBegan: () -> Void
    var onExportEnded: () -> Void
    var dragURL: URL?
    var isDirectory: Bool

    func makeNSView(context: Context) -> FileInteractionNSView {
        let view = FileInteractionNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: FileInteractionNSView, context: Context) {
        view.onSelect = onSelect
        view.onOpen = onOpen
        view.onPreview = onPreview
        view.onRemove = onRemove
        view.onExportBegan = onExportBegan
        view.onExportEnded = onExportEnded
        view.dragURL = dragURL
        view.isDirectory = isDirectory
    }
}

@MainActor
final class FileInteractionNSView: NSView, NSDraggingSource {
    var onSelect: () -> Void = {}
    var onOpen: () -> Void = {}
    var onPreview: () -> Void = {}
    var onRemove: () -> Void = {}
    var onExportBegan: () -> Void = {}
    var onExportEnded: () -> Void = {}
    var dragURL: URL?
    var isDirectory = false
    private var mouseDownPoint: NSPoint = .zero
    private var didStartDrag = false
    private var dragRetain: AnyObject?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = window?.currentEvent,
           event.type == .rightMouseDown || event.type == .rightMouseUp {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
        onSelect()
        if event.clickCount >= 2 {
            onOpen()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let dragURL else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        guard distance >= 4 else { return }
        didStartDrag = true
        onExportBegan()
        let export = FileStagingTransfer.draggingExport(for: dragURL, isDirectory: isDirectory)
        dragRetain = export.retain
        let item = NSDraggingItem(pasteboardWriter: export.writer)
        let image = FileThumbnail.load(url: dragURL, isDirectory: isDirectory, isMissing: false)
        let origin = NSPoint(x: point.x - 36, y: point.y - 36)
        item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: 72, height: 72)), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            onPreview()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onOpen()
            return
        }
        super.keyDown(with: event)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragRetain = nil
        onExportEnded()
    }
}
