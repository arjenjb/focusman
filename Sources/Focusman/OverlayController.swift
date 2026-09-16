import AppKit

/// Keeps one dim panel per display, immediately behind the active window.
final class OverlayController {
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var menuWindows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var currentWindows = UndimmedWindows()
    private let quitOnBackgroundClick: Bool
    var onBackgroundClick: (() -> Void)?

    init(quitOnBackgroundClick: Bool = false) {
        self.quitOnBackgroundClick = quitOnBackgroundClick
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        rebuild()
    }

    @objc private func screensChanged() {
        rebuild()
        apply(windows: currentWindows, animated: false)
    }

    private func rebuild() {
        var live: [CGDirectDisplayID: OverlayWindow] = [:]
        var liveMenus: [CGDirectDisplayID: OverlayWindow] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let window = windows[id] ?? OverlayWindow()
            window.attach(to: screen)
            live[id] = window

            // Raising the desktop panel to dim the menu bar would also cover
            // the active window. Use an independent strip instead.
            let menu = menuWindows[id] ?? OverlayWindow()
            let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            menu.setFrame(CGRect(x: screen.frame.minX,
                                 y: screen.frame.maxY - height,
                                 width: screen.frame.width, height: height), display: false)
            menu.level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 1)
            liveMenus[id] = menu
        }
        for (id, window) in windows where live[id] == nil { window.orderOut(nil) }
        for (id, window) in menuWindows where liveMenus[id] == nil { window.orderOut(nil) }
        windows = live
        menuWindows = liveMenus
    }

    func apply(windows selection: UndimmedWindows, animated: Bool) {
        currentWindows = selection
        // A dismissible focus session has one clear window and a solid clickable
        // background. Do not let saved app/exclusion cutouts swallow clicks.
        let selection = quitOnBackgroundClick ? UndimmedWindows(front: selection.front) : selection
        let settings = Settings.shared
        let suppressed = !settings.enabled
            || selection.all.isEmpty
            || (settings.skipFullScreen && selection.all.contains { Geometry.isFullScreen($0.rect) })

        let dismiss: (() -> Void)? = quitOnBackgroundClick && !suppressed && settings.intensity > 0
            ? { [weak self] in self?.onBackgroundClick?() } : nil

        for window in windows.values {
            window.setBackgroundClickHandler(dismiss)
            // Only additional windows need cutouts. WindowServer draws the
            // active window above this panel, without a corner estimate.
            window.update(holes: selection.additional.map(\.rect),
                          intensity: suppressed ? 0 : settings.intensity,
                          radius: settings.cornerRadius,
                          animated: animated)
            if suppressed {
                window.orderOut(nil)
            } else {
                window.place(below: selection.front?.id)
            }
        }

        for menu in menuWindows.values {
            menu.setBackgroundClickHandler(settings.dimMenuBar ? dismiss : nil)
            if suppressed || !settings.dimMenuBar {
                menu.orderOut(nil)
            } else {
                menu.update(holes: [], intensity: settings.intensity, radius: 0, animated: animated)
                menu.orderFrontRegardless()
            }
        }
    }
}
