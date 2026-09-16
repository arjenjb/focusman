import AppKit
import XCTest
@testable import Focusman

final class OverlayTests: XCTestCase {
    func testDismissiblePanelConsumesFirstClickWithoutTakingFocus() throws {
        _ = NSApplication.shared
        let panel = OverlayWindow()
        panel.setFrame(CGRect(x: 200, y: 200, width: 100, height: 100), display: false)
        XCTAssertTrue(panel.ignoresMouseEvents)
        let keyWindow = NSApp.keyWindow
        var dismissals = 0
        panel.setBackgroundClickHandler { dismissals += 1 }
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(try XCTUnwrap(panel.contentView).acceptsFirstMouse(for: nil))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        panel.contentView?.layoutSubtreeIfNeeded()

        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                                                    location: CGPoint(x: 50, y: 50),
                                                    modifierFlags: [], timestamp: 0,
                                                    windowNumber: panel.windowNumber,
                                                    context: nil, eventNumber: 1,
                                                    clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        panel.setBackgroundClickHandler(nil)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(try XCTUnwrap(panel.contentView).acceptsFirstMouse(for: nil))
    }

    func testPanelOrdersBelowAnotherAppsWindowAndCanRestoreOrder() throws {
        _ = NSApplication.shared
        let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let target = try XCTUnwrap(entries.first {
            ($0[kCGWindowLayer as String] as? Int) == 0
                && ($0[kCGWindowOwnerPID as String] as? pid_t) != ProcessInfo.processInfo.processIdentifier
        }?[kCGWindowNumber as String] as? CGWindowID)
        let panel = OverlayWindow()
        panel.setFrame(CGRect(x: 200, y: 200, width: 100, height: 100), display: false)
        defer { panel.orderOut(nil) }

        for _ in 0..<2 {
            panel.place(below: target)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            let ordered = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let ids = ordered.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
            XCTAssertEqual(panel.level, .normal)
            XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: target)),
                              try XCTUnwrap(ids.firstIndex(of: CGWindowID(panel.windowNumber))))
            panel.orderFrontRegardless()
        }
    }

    func testFrontWindowDoesNotPunchAnEstimatedCornerIntoDimLayer() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let rect = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 300, height: 200)
        let target = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        target.backgroundColor = .clear
        target.isOpaque = false
        target.orderFrontRegardless()
        let settings = Settings.shared
        let saved = (settings.enabled, settings.intensity, settings.dimMenuBar)
        settings.enabled = true
        settings.intensity = 0 // Exercise the real controller without dimming the test desktop.
        settings.dimMenuBar = false
        let existing = Set(NSApp.windows.map(\.windowNumber))
        defer {
            for panel in NSApp.windows where !existing.contains(panel.windowNumber) { panel.orderOut(nil) }
            target.orderOut(nil)
            settings.enabled = saved.0
            settings.intensity = saved.1
            settings.dimMenuBar = saved.2
        }
        let controller = OverlayController()
        let front = SampledWindow(id: CGWindowID(target.windowNumber), pid: 1, bundleID: "test", rect: rect)
        controller.apply(windows: UndimmedWindows(front: front), animated: false)
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0 is OverlayWindow && !existing.contains($0.windowNumber)
                && $0.level == .normal && $0.frame == screen.frame
        })
        panel.contentView?.layoutSubtreeIfNeeded()
        let mask = try XCTUnwrap(panel.contentView?.layer?.sublayers?.first?.mask as? CAShapeLayer)
        let path = try XCTUnwrap(mask.path)
        // A filled panel behind the window lets WindowServer determine the shape.
        // An estimated cutout would leave gaps here for rounder native corners.
        for inset: CGFloat in [1, 5, 12, 25] {
            let point = CGPoint(x: rect.minX - panel.frame.minX + inset,
                                y: rect.minY - panel.frame.minY + inset)
            XCTAssertTrue(path.contains(point, using: .evenOdd))
        }
        XCTAssertTrue(path.contains(CGPoint(x: rect.midX - panel.frame.minX,
                                           y: rect.midY - panel.frame.minY), using: .evenOdd))
        withExtendedLifetime(controller) {}
    }

    func testSameBoundsWithDifferentWindowIdentityStillChangesSelection() {
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        let a = SampledWindow(id: 1, pid: 1, bundleID: "test", rect: rect)
        let b = SampledWindow(id: 2, pid: 1, bundleID: "test", rect: rect)
        XCTAssertNotEqual(UndimmedWindows(front: a), UndimmedWindows(front: b))
        XCTAssertEqual(UndimmedWindows(front: a, additional: [b]).all, [a, b])
    }
}
