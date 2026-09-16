import AppKit

struct SampledWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String
    /// Cocoa (bottom-left origin) global coordinates.
    let rect: CGRect
}

struct UndimmedWindows: Equatable {
    var front: SampledWindow?
    var additional: [SampledWindow] = []

    var all: [SampledWindow] { (front.map { [$0] } ?? []) + additional }
}

/// Tracks window identities as well as bounds so the overlay can sit behind them.
///
/// NSWorkspace notifications track app and Space changes. Polling the public
/// window list tracks ordering and bounds, including changes within one app.
/// Neither path needs Accessibility access.
final class FrontWindowTracker {
    var onChange: ((UndimmedWindows, Bool) -> Void)?

    /// Bundle ID of the last non-Focusman frontmost app, for the "never dim this app" menu item.
    private(set) var lastFrontBundleID: String?
    private(set) var lastFrontAppName: String?

    private var pollTimer: Timer?
    private var mouseMonitor: Any?
    private var lastWindows = UndimmedWindows()
    private var fastPolling = false

    // MARK: - Lifecycle

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in names {
            nc.addObserver(self, selector: #selector(frontAppChanged), name: name, object: nil)
        }

        // Poll faster during dragging to keep additional-window cutouts aligned.
        // Monitoring mouse events does not require Accessibility access.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.fastPolling = (event.type == .leftMouseDown)
            self?.retimePolling()
        }

        retimePolling()
        refresh(force: true)
    }

    @objc private func frontAppChanged() {
        refresh(force: true)
    }

    private func retimePolling() {
        pollTimer?.invalidate()
        let interval = fastPolling ? 1.0 / 60.0 : 0.25
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Sampling

    func refresh(force: Bool = false) {
        let windows = undimmedWindows()
        let changed = force || windows != lastWindows
        lastWindows = windows
        // Reassert ordering even when bounds are unchanged: another app can
        // reorder windows without moving them or changing the focused app.
        onChange?(windows, changed)
    }

    private func undimmedWindows() -> UndimmedWindows {
        let windows = onScreenWindows()
        var result = UndimmedWindows()

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastFrontBundleID = front.bundleIdentifier
            lastFrontAppName = front.localizedName
            for window in windows where window.pid == front.processIdentifier {
                if result.front == nil {
                    result.front = window
                } else {
                    result.additional.append(window)
                }
                if Settings.shared.mode == .window { break }
            }
        }

        let excluded = Settings.shared.excludedBundleIDs
        if !excluded.isEmpty {
            for window in windows where excluded.contains(window.bundleID) {
                if !result.all.contains(where: { $0.id == window.id }) { result.additional.append(window) }
            }
        }

        return result
    }

    private func onScreenWindows() -> [SampledWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var bundleCache: [pid_t: String] = [:]
        var out: [SampledWindow] = []

        // The list is ordered front to back, so the first layer-0 match is the front window.
        for entry in raw {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            // Filter out tooltips, drag proxies and invisible helper windows.
            guard alpha > 0.05, quartz.width >= 48, quartz.height >= 48 else { continue }

            let bundleID: String
            if let cached = bundleCache[pid] {
                bundleID = cached
            } else {
                bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                bundleCache[pid] = bundleID
            }

            out.append(SampledWindow(id: id, pid: pid, bundleID: bundleID, rect: Geometry.cocoaRect(fromQuartz: quartz)))
        }

        return out
    }
}
