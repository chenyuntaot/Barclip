import AppKit
import CoreGraphics

struct DropShelfPlacement: Equatable, Sendable {
    var frame: CGRect
}

enum MenuBarDropAnchor {
    static let shelfSize = CGSize(width: 236, height: 104)
    @MainActor
    private static var rememberedAnchor: CGRect?

    @MainActor
    static func rememberOpenExtra() {
        let extras = NSApp.windows.filter { window in
            window.isVisible
                && window.frame.width >= 320
                && window.frame.width <= 560
                && window.frame.height >= 180
        }
        guard let extra = extras.first else { return }
        let screen = extra.screen ?? NSScreen.main
        let barTop = screen?.frame.maxY ?? extra.frame.maxY
        let barHeight: CGFloat = 22
        rememberedAnchor = CGRect(
            x: extra.frame.midX - 12,
            y: barTop - barHeight,
            width: 24,
            height: barHeight
        )
    }

    @MainActor
    static func rememberedStatusItemFrame() -> CGRect? {
        rememberedAnchor
    }

    static func cocoaRect(fromCGWindowRect rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryDisplayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func statusItemFrames(
        windowRects: [CGRect],
        screens: [CGRect]
    ) -> [CGRect] {
        windowRects.filter { rect in
            guard rect.height >= 10, rect.height <= 44, rect.width >= 10, rect.width <= 120 else { return false }
            return screens.contains { screen in
                rect.minY >= screen.maxY - 44 && screen.intersects(rect)
            }
        }
    }

    static func shelfPlacement(
        size: CGSize = shelfSize,
        mouseLocation: CGPoint,
        screens: [CGRect],
        statusItemFrames: [CGRect],
        rememberedAnchor: CGRect? = nil
    ) -> DropShelfPlacement {
        let screen = screens.first { $0.contains(mouseLocation) }
            ?? screens.first { frame in statusItemFrames.contains { frame.intersects($0) } }
            ?? screens.max(by: { $0.maxX < $1.maxX })
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let item = statusItemFrames.first { screen.intersects($0) }
            ?? rememberedAnchor.flatMap { screen.intersects($0) ? $0 : nil }
        let anchorX = item?.midX ?? (screen.maxX - 148)
        var x = anchorX - size.width / 2
        x = min(max(screen.minX + 8, x), max(screen.minX + 8, screen.maxX - size.width - 8))
        let y: CGFloat
        if let item {
            y = item.minY - 2 - size.height
        } else {
            y = screen.maxY - 24 - size.height
        }
        return DropShelfPlacement(
            frame: CGRect(x: x, y: max(screen.minY + 8, y), width: size.width, height: size.height)
        )
    }

    @MainActor
    static func currentPlacement(excluding excludedWindowNumbers: Set<Int> = []) -> DropShelfPlacement {
        let screens = NSScreen.screens.map(\.frame)
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 900
        let pid = ProcessInfo.processInfo.processIdentifier
        let windowRects = cgWindowRects(pid: pid, primaryDisplayHeight: primaryHeight, excluding: excludedWindowNumbers)
            + appOwnedStatusItemFrames()
        let items = statusItemFrames(windowRects: windowRects, screens: screens)
        return shelfPlacement(
            mouseLocation: mouse,
            screens: screens,
            statusItemFrames: items,
            rememberedAnchor: rememberedStatusItemFrame()
        )
    }

    @MainActor
    static func currentShelfFrame(excluding excludedWindowNumbers: Set<Int> = []) -> CGRect {
        currentPlacement(excluding: excludedWindowNumbers).frame
    }

    @MainActor
    private static func appOwnedStatusItemFrames() -> [CGRect] {
        NSApp.windows.compactMap { window in
            let frame = window.frame
            guard frame.height <= 48, frame.width <= 120, frame.width >= 8 else { return nil }
            guard let screen = window.screen ?? NSScreen.main else { return nil }
            guard frame.minY >= screen.frame.maxY - 48 else { return nil }
            return frame
        }
    }

    private static func cgWindowRects(pid: pid_t, primaryDisplayHeight: CGFloat, excluding: Set<Int>) -> [CGRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { return nil }
            if let number = window[kCGWindowNumber as String] as? Int, excluding.contains(number) { return nil }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return cocoaRect(fromCGWindowRect: rect, primaryDisplayHeight: primaryDisplayHeight)
        }
    }
}
