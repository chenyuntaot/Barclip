import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FileThumbnail {
    static func icon(for item: FileStagingItem) -> NSImage {
        let url = item.isMissing ? nil : (item.resolvedURL ?? item.resolvingBookmarkURL())
        return load(url: url, isDirectory: item.isDirectory, isMissing: item.isMissing)
    }

    static func load(url: URL?, isDirectory: Bool, isMissing: Bool) -> NSImage {
        if isMissing || url == nil {
            return NSWorkspace.shared.icon(for: isDirectory ? .folder : .data)
        }
        let fileURL = url!
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        if !isDirectory, let thumbnail = imageThumbnail(at: fileURL) {
            return thumbnail
        }
        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    static func imageThumbnail(at url: URL, maxPixel: CGFloat = 160) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        guard let type = CGImageSourceGetType(source) as String? else { return nil }
        guard UTType(type)?.conforms(to: .image) == true else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func previewImage(at url: URL) -> NSImage? {
        if let thumbnail = imageThumbnail(at: url, maxPixel: 1_600) {
            return thumbnail
        }
        if let image = NSImage(contentsOf: url), image.size.width > 0 {
            return image
        }
        return nil
    }
}
