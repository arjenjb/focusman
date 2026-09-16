import AppKit

/// A never-focused dim panel; optionally consumes background clicks to dismiss Focusman.
final class OverlayWindow: NSPanel {
    private let dimView = DimView(frame: .zero)

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // clicks pass straight through to whatever is underneath
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        sharingType = .none                // keep the dim out of screenshots and screen shares
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        level = .floating
        contentView = dimView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func attach(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
    }

    /// Keep the real front window above the dim layer, including its own shape
    /// and shadow. Reassert this after window activation and ordering changes.
    func place(below windowID: CGWindowID?) {
        let desiredLevel: NSWindow.Level = windowID == nil ? .floating : .normal
        if level != desiredLevel { level = desiredLevel }
        if let windowID {
            order(.below, relativeTo: Int(windowID))
        } else {
            orderFrontRegardless()
        }
    }

    func setBackgroundClickHandler(_ handler: (() -> Void)?) {
        ignoresMouseEvents = handler == nil
        dimView.onBackgroundClick = handler
    }

    /// `holes` are in global Cocoa coordinates; convert to view space and clip.
    func update(holes: [CGRect], intensity: CGFloat, radius: CGFloat, animated: Bool) {
        let local = holes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        dimView.apply(holes: local, intensity: intensity, radius: radius, animated: animated)
    }
}

/// Solid black layer with a CAShapeLayer mask. The mask path is the full bounds
/// plus a rounded rect per hole, filled even-odd, so the holes end up transparent.
final class DimView: NSView {
    var onBackgroundClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        onBackgroundClick != nil
    }

    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }
    override func rightMouseDown(with event: NSEvent) { onBackgroundClick?() }
    override func otherMouseDown(with event: NSEvent) { onBackgroundClick?() }

    private let dimLayer = CALayer()
    private let maskLayer = CAShapeLayer()

    private var holes: [CGRect] = []
    private var radius: CGFloat = 11

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()

        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.cgColor
        dimLayer.mask = maskLayer
        layer?.addSublayer(dimLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        dimLayer.frame = bounds
        maskLayer.frame = bounds
        rebuildMask()
    }

    func apply(holes: [CGRect], intensity: CGFloat, radius: CGFloat, animated: Bool) {
        if self.holes != holes || self.radius != radius || maskLayer.path == nil {
            self.holes = holes
            self.radius = radius
            rebuildMask()
        }
        setOpacity(Float(intensity), animated: animated)
    }

    private func rebuildMask() {
        let path = CGMutablePath()
        path.addRect(bounds)
        for hole in holes where hole.intersects(bounds) {
            path.addPath(CGPath(roundedRect: hole,
                                cornerWidth: radius,
                                cornerHeight: radius,
                                transform: nil))
        }
        // Deliberately not animated: interpolating between paths with different
        // subpath counts produces smearing. The fade below carries the transition.
        maskLayer.path = path
    }

    private func setOpacity(_ value: Float, animated: Bool) {
        guard dimLayer.opacity != value else { return }
        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = dimLayer.opacity
            fade.toValue = value
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dimLayer.add(fade, forKey: "opacity")
        } else {
            dimLayer.removeAnimation(forKey: "opacity")
        }
        dimLayer.opacity = value
    }
}
