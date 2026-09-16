import AppKit

enum Geometry {
    /// CGWindowList reports bounds in the Quartz global space: origin at the *top* left
    /// of the primary display, y growing downwards. NSWindow/NSScreen use the bottom
    /// left of that same display with y growing up. Flip about the primary screen.
    static func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let flippedY = primary.frame.maxY - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }

    /// A window that exactly fills a display is almost certainly full screen.
    static func isFullScreen(_ rect: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            abs(screen.frame.width - rect.width) < 2 && abs(screen.frame.height - rect.height) < 2
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
