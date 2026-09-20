import AppKit
import QuickLookUI
import UniformTypeIdentifiers

@MainActor
final class FileQuickLookController: NSObject, NSWindowDelegate {
    static let shared = FileQuickLookController()

    private let panel: NSPanel
    private let previewView: QLPreviewView
    private let imageView: NSImageView
    private var currentURL: URL?
    private var currentClipboardImageID: UUID?
    private var accessURL: URL?

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        previewView = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        imageView = NSImageView()
        super.init()
        panel.title = String(localized: "预览")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        previewView.shouldCloseWithWindow = false
        previewView.autoresizingMask = [.width, .height]
        imageView.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        previewView.frame = content.bounds
        imageView.frame = content.bounds
        content.addSubview(previewView)
        content.addSubview(imageView)
        panel.contentView = content
        imageView.isHidden = true
    }

    func present(urls: [URL], selected: URL) -> Bool {
        present(url: selected)
    }

    @discardableResult
    func present(item: FileStagingItem) -> Bool {
        guard let url = item.resolvingBookmarkURL() ?? item.resolvedURL else { return false }
        return present(url: url)
    }

    @discardableResult
    func present(url: URL) -> Bool {
        let fileURL = url.standardizedFileURL
        if panel.isVisible, currentURL == fileURL {
            hide()
            return true
        }
        retainAccess(to: fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            releaseAccess()
            return false
        }
        currentURL = fileURL
        currentClipboardImageID = nil
        panel.title = fileURL.lastPathComponent
        let image = FileThumbnail.previewImage(at: fileURL)
        if image != nil || isImageFile(fileURL) {
            imageView.image = image ?? NSWorkspace.shared.icon(forFile: fileURL.path)
            imageView.isHidden = false
            previewView.isHidden = true
            previewView.previewItem = nil
        } else {
            imageView.image = nil
            imageView.isHidden = true
            previewView.isHidden = false
        }
        showPanel()
        if imageView.isHidden {
            previewView.previewItem = fileURL as NSURL
        }
        return true
    }

    @discardableResult
    func present(imagePNG: Data, id: UUID) -> Bool {
        guard let image = NSImage(data: imagePNG), image.size.width > 0, image.size.height > 0 else {
            return false
        }
        if panel.isVisible, currentClipboardImageID == id {
            hide()
            return true
        }
        releaseAccess()
        currentURL = nil
        currentClipboardImageID = id
        panel.title = String(localized: "预览")
        previewView.previewItem = nil
        previewView.isHidden = true
        imageView.image = image
        imageView.isHidden = false
        showPanel()
        return true
    }

    func hide() {
        panel.orderOut(nil)
        previewView.previewItem = nil
        imageView.image = nil
        currentURL = nil
        currentClipboardImageID = nil
        releaseAccess()
    }

    func windowWillClose(_ notification: Notification) {
        previewView.previewItem = nil
        imageView.image = nil
        currentURL = nil
        currentClipboardImageID = nil
        releaseAccess()
    }

    private func showPanel() {
        if let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
            var frame = panel.frame
            frame.origin.x = screen.midX - frame.width / 2
            frame.origin.y = screen.midY - frame.height / 2
            panel.setFrame(frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func isImageFile(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            return true
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image) {
            return true
        }
        return false
    }

    private func retainAccess(to url: URL) {
        releaseAccess()
        if url.startAccessingSecurityScopedResource() {
            accessURL = url
        }
    }

    private func releaseAccess() {
        accessURL?.stopAccessingSecurityScopedResource()
        accessURL = nil
    }
}
