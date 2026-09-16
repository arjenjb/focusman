import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlays: OverlayController
    private let tracker = FrontWindowTracker()

    private let intensitySteps: [Double] = [0.25, 0.40, 0.55, 0.70, 0.85]

    init(options: LaunchOptions) {
        overlays = OverlayController(quitOnBackgroundClick: options.quitOnBackgroundClick)
        super.init()
        overlays.onBackgroundClick = { NSApplication.shared.terminate(nil) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

        Settings.shared.onChange = { [weak self] in
            self?.tracker.refresh(force: true)
            self?.rebuildMenu()
        }

        tracker.onChange = { [weak self] windows, changed in
            self?.overlays.apply(windows: windows, animated: changed)
        }

        tracker.start()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled",
                                           accessibilityDescription: "Focusman")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let settings = Settings.shared
        let menu = NSMenu()

        menu.addItem(item(title: "Dimming", action: #selector(toggleEnabled), on: settings.enabled))
        menu.addItem(.separator())

        menu.addItem(header("Intensity"))
        for step in intensitySteps {
            let entry = item(title: "\(Int(step * 100))%",
                             action: #selector(setIntensity(_:)),
                             on: abs(Double(settings.intensity) - step) < 0.01)
            entry.representedObject = step
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(header("Keep lit"))
        menu.addItem(item(title: "Front window only",
                          action: #selector(setModeWindow),
                          on: settings.mode == .window))
        menu.addItem(item(title: "All windows of front app",
                          action: #selector(setModeApp),
                          on: settings.mode == .app))

        menu.addItem(.separator())
        menu.addItem(item(title: "Dim the menu bar too",
                          action: #selector(toggleMenuBar),
                          on: settings.dimMenuBar))
        menu.addItem(item(title: "Pause in full screen",
                          action: #selector(toggleFullScreen),
                          on: settings.skipFullScreen))

        if let bundleID = tracker.lastFrontBundleID {
            let name = tracker.lastFrontAppName ?? bundleID
            menu.addItem(item(title: "Never dim \(name)",
                              action: #selector(toggleExclusion),
                              on: settings.excludedBundleIDs.contains(bundleID)))
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Focusman", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func item(title: String, action: Selector, on: Bool) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.state = on ? .on : .off
        return entry
    }

    private func header(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    // MARK: - Actions

    @objc private func toggleEnabled() { Settings.shared.enabled.toggle() }
    @objc private func toggleMenuBar() { Settings.shared.dimMenuBar.toggle() }
    @objc private func toggleFullScreen() { Settings.shared.skipFullScreen.toggle() }
    @objc private func setModeWindow() { Settings.shared.mode = .window }
    @objc private func setModeApp() { Settings.shared.mode = .app }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Settings.shared.intensity = CGFloat(value)
    }

    @objc private func toggleExclusion() {
        guard let bundleID = tracker.lastFrontBundleID else { return }
        Settings.shared.toggleExclusion(bundleID)
    }
}
