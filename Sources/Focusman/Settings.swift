import AppKit

enum DimMode: String {
    /// Only the single frontmost window stays lit.
    case window
    /// Every window of the frontmost app stays lit.
    case app
}

final class Settings {
    static let shared = Settings()

    /// Called after any mutation so the overlay can be re-applied.
    var onChange: (() -> Void)?

    private enum Key {
        static let enabled = "enabled"
        static let intensity = "intensity"
        static let mode = "mode"
        static let dimMenuBar = "dimMenuBar"
        static let skipFullScreen = "skipFullScreen"
        static let cornerRadius = "cornerRadius"
        static let excluded = "excludedBundleIDs"
    }

    private let store = UserDefaults.standard

    private init() {
        // Carry existing preferences across the app's bundle-identifier rename.
        if Bundle.main.bundleIdentifier == "nl.arjenjb.focusman",
           store.persistentDomain(forName: "nl.arjenjb.focusman") == nil,
           let previous = store.persistentDomain(forName: "com.example.haze") {
            store.setPersistentDomain(previous, forName: "nl.arjenjb.focusman")
        }
        store.register(defaults: [
            Key.enabled: true,
            Key.intensity: 0.55,
            Key.mode: DimMode.window.rawValue,
            Key.dimMenuBar: false,
            Key.skipFullScreen: true,
            Key.cornerRadius: 11.0,
            Key.excluded: [String]()
        ])
    }

    var enabled: Bool {
        get { store.bool(forKey: Key.enabled) }
        set { store.set(newValue, forKey: Key.enabled); onChange?() }
    }

    /// 0 = no dimming, 0.95 = nearly black.
    var intensity: CGFloat {
        get { CGFloat(min(max(store.double(forKey: Key.intensity), 0), 0.95)) }
        set { store.set(Double(newValue), forKey: Key.intensity); onChange?() }
    }

    var mode: DimMode {
        get { DimMode(rawValue: store.string(forKey: Key.mode) ?? "") ?? .window }
        set { store.set(newValue.rawValue, forKey: Key.mode); onChange?() }
    }

    /// When true separate strips dim the menu bar above the desktop overlay.
    var dimMenuBar: Bool {
        get { store.bool(forKey: Key.dimMenuBar) }
        set { store.set(newValue, forKey: Key.dimMenuBar); onChange?() }
    }

    /// Turn dimming off entirely while a full-screen window is in front.
    var skipFullScreen: Bool {
        get { store.bool(forKey: Key.skipFullScreen) }
        set { store.set(newValue, forKey: Key.skipFullScreen); onChange?() }
    }

    /// Fallback radius for additional-window cutouts; the active window uses native layering.
    var cornerRadius: CGFloat {
        get { CGFloat(store.double(forKey: Key.cornerRadius)) }
        set { store.set(Double(newValue), forKey: Key.cornerRadius); onChange?() }
    }

    /// Apps whose windows are never dimmed, even in the background.
    var excludedBundleIDs: Set<String> {
        get { Set(store.stringArray(forKey: Key.excluded) ?? []) }
        set { store.set(Array(newValue).sorted(), forKey: Key.excluded); onChange?() }
    }

    func toggleExclusion(_ bundleID: String) {
        var current = excludedBundleIDs
        if current.contains(bundleID) {
            current.remove(bundleID)
        } else {
            current.insert(bundleID)
        }
        excludedBundleIDs = current
    }
}
