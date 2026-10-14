import AppKit
import SwiftUI

@main
@MainActor
enum TapeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = TapeAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class TapeAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: TapeController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var guideWindow: NSWindow?
    private var tabOverlays: TabOverlayManager?
    private var previewMode = false
    private var actions: [ObjectIdentifier: () -> Void] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        previewMode = CommandLine.arguments.contains("--ui-preview")
        controller = TapeController(previewOnly: previewMode)
        if !previewMode { tabOverlays = TabOverlayManager(controller: controller) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = TapeMark.image()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        controller.onStatusChange = { [weak self] in self?.refreshStatus() }
        refreshStatus()
        if previewMode { openSettings(); return }
        UpdateService.shared.start()
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.submenu?.addItem(withTitle: "Quit Tape", action: #selector(quit), keyEquivalent: "q").target = self
        main.addItem(app)
        NSApp.mainMenu = main
        if !UserDefaults.standard.bool(forKey: "completedOnboarding") || !controller.hasAccessibility { openGuide() }
        else { controller.resume() }
    }
    func applicationDidBecomeActive(_ notification: Notification) { controller?.checkPermission() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }
    private func refreshStatus() {
        statusItem?.button?.toolTip = controller.isPaused ? "Tape — paused" : "Tape — \(controller.managedCount) windows"
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        controller.checkPermission()
        actions.removeAll()
        menu.removeAllItems()
        item("Tape · \(controller.isPaused ? "Paused" : "\(controller.managedCount) windows")", menu: menu, enabled: false) {}
        if let message = controller.message { item(message, menu: menu, enabled: false) {} }
        item(controller.isRestoring ? "Restoring windows…" : controller.isPaused ? "Start Tape" : "Pause and Restore Windows", menu: menu,
             key: "p", modifiers: [.control, .option], enabled: !controller.isRestoring && !previewMode) { [weak self] in
            guard let self else { return }
            if self.controller.hasAccessibility { self.controller.perform(.togglePause) } else { self.openGuide() }
        }
        menu.addItem(.separator())
        let enabled = controller.canArrange
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        item("Focus Previous Window", menu: menu, key: left, modifiers: [.control, .option], enabled: enabled) { [weak self] in self?.controller.perform(.strip(.left)) }
        item("Focus Next Window", menu: menu, key: right, modifiers: [.control, .option], enabled: enabled) { [weak self] in self?.controller.perform(.strip(.right)) }
        let windows = NSMenu(); windows.autoenablesItems = false
        for choice in controller.windowChoices {
            let entry = item(choice.name, menu: windows) { [weak self] in self?.controller.chooseWindow(choice.id) }
            entry.state = choice.selected ? .on : .off
        }
        let choices = item("Go to Window", menu: menu, enabled: enabled) {}; choices.submenu = windows
        let width = NSMenu(); width.autoenablesItems = false
        for (title, fraction) in [("One Third", 1.0 / 3), ("Half", 0.5), ("Two Thirds", 2.0 / 3), ("Full", 1.0)] {
            item(title, menu: width, enabled: enabled) { [weak self] in self?.controller.setWidth(fraction) }
        }
        width.addItem(.separator())
        item("Cycle Width", menu: width, key: "w", modifiers: [.control, .option], enabled: enabled) { [weak self] in self?.controller.perform(.strip(.nextWidth)) }
        let widths = item("Window Width", menu: menu, enabled: enabled) {}; widths.submenu = width
        let allWidths = NSMenu(); allWidths.autoenablesItems = false
        for (title, fraction) in [("One Third", 1.0 / 3), ("Half", 0.5), ("Two Thirds", 2.0 / 3), ("Full", 1.0)] {
            item(title, menu: allWidths, enabled: enabled) { [weak self] in self?.controller.setAllWidths(fraction) }
        }
        let all = item("All Window Widths", menu: menu, enabled: enabled) {}; all.submenu = allWidths
        let shared = item("Resize Windows Together", menu: menu) { [weak self] in
            guard let self else { return }; self.controller.settings.sharedWidths.toggle()
        }
        shared.state = controller.settings.sharedWidths ? .on : .off
        let groups = NSMenu(); groups.autoenablesItems = false
        for key in [StripActionKey.joinLeft, .joinRight, .detach, .toggleMode, .previousTab, .nextTab, .tabLeft, .tabRight, .taller, .shorter, .equalHeights] {
            item(key.label, menu: groups, enabled: enabled) { [weak self] in self?.controller.perform(.strip(key)) }
        }
        let stacks = item("Stacks and Tabs", menu: menu, enabled: enabled) {}; stacks.submenu = groups
        let destinations = NSMenu(); destinations.autoenablesItems = false
        for display in controller.displayChoices where display.enabled && display.id != controller.focusedDisplayID {
            item(display.name, menu: destinations, enabled: controller.canSendToDisplay) { [weak self] in self?.controller.sendWindow(to: display.id) }
        }
        destinations.addItem(.separator())
        item("Next Display", menu: destinations, key: "d", modifiers: [.control, .option], enabled: controller.canSendToDisplay) { [weak self] in self?.controller.perform(.nextDisplay) }
        let moveDisplay = item("Move to Display", menu: menu, enabled: controller.canSendToDisplay) {}; moveDisplay.submenu = destinations

        item("Move Column Left", menu: menu, key: left, modifiers: [.control, .option, .shift], enabled: enabled) { [weak self] in self?.controller.perform(.strip(.moveLeft)) }
        item("Move Column Right", menu: menu, key: right, modifiers: [.control, .option, .shift], enabled: enabled) { [weak self] in self?.controller.perform(.strip(.moveRight)) }
        item("Float / Tile Focused Window", menu: menu, key: "f", modifiers: [.control, .option], enabled: !controller.isPaused && !previewMode) { [weak self] in self?.controller.perform(.toggleFloat) }
        menu.addItem(.separator())
        item("Choose Managed Apps…", menu: menu) { [weak self] in SettingsNavigation.shared.open(.apps); self?.openSettings() }
        let scope = NSMenu(); scope.autoenablesItems = false
        let lock = item("Lock Tape to Selected Windows", menu: scope, enabled: !controller.isPaused && !previewMode) { [weak self] in
            guard let self else { return }; self.controller.setManageAllWindows(!self.controller.manageAllWindows)
        }
        lock.state = controller.manageAllWindows ? .off : .on
        scope.addItem(.separator())
        for choice in controller.managedWindowChoices {
            let entry = item(choice.name, menu: scope, enabled: !controller.isPaused && !previewMode) { [weak self] in
                self?.controller.setWindowManaged(choice.id, !choice.managed)
            }
            entry.state = choice.managed ? .on : .off
        }
        let selection = item("Choose Managed Windows", menu: menu, enabled: !controller.isPaused && !previewMode) {}; selection.submenu = scope
        item("Settings…", menu: menu, key: ",", modifiers: .command) { [weak self] in self?.openSettings() }
        item("How to Use Tape…", menu: menu) { [weak self] in self?.openGuide() }
        item("Check for Updates…", menu: menu, enabled: !UpdateService.shared.isBusy) { [weak self] in
            UpdateService.shared.check(); SettingsNavigation.shared.open(.general, card: "Updates"); self?.openSettings()
        }
        menu.addItem(.separator())
        item("Quit Tape", menu: menu, key: "q", modifiers: .command) { [weak self] in self?.quit() }
    }
    @discardableResult private func item(_ title: String, menu: NSMenu, key: String = "", modifiers: NSEvent.ModifierFlags = [], enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuItem(_:)), keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers; item.isEnabled = enabled
        actions[ObjectIdentifier(item)] = action
        menu.addItem(item)
        return item
    }
    @objc private func runMenuItem(_ sender: NSMenuItem) { actions[ObjectIdentifier(sender)]?() }
    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Tape Settings", view: SettingsView(controller: controller, settings: controller.settings, showGuide: { [weak self] in self?.openGuide() }), size: NSSize(width: 980, height: 680))
            settingsWindow?.styleMask.formUnion([.resizable, .fullSizeContentView])
            settingsWindow?.titleVisibility = .hidden
            settingsWindow?.titlebarAppearsTransparent = true
            settingsWindow?.isMovableByWindowBackground = true
            settingsWindow?.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
            settingsWindow?.minSize = NSSize(width: 640, height: 480)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        controller.checkPermission()
    }
    @objc private func openGuide() {
        if guideWindow == nil {
            let guide = OnboardingView(controller: controller) { [weak self] in
                UserDefaults.standard.set(true, forKey: "completedOnboarding")
                self?.guideWindow?.close(); self?.guideWindow = nil
            }
            guideWindow = makeWindow(title: "How to Use Tape", view: guide, size: NSSize(width: 600, height: 620))
        }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
        controller.checkPermission()
    }
    private func makeWindow<Content: View>(title: String, view: Content, size: NSSize) -> NSWindow {
        let visible = NSScreen.main?.visibleFrame.size ?? size
        let fit = NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fit), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view); host.sizingOptions = []
        window.contentView = host
        window.center()
        return window
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if previewMode { return .terminateNow }
        controller.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

enum TapeMark {
    static func image(size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor.labelColor.setFill()
            let path = NSBezierPath()
            let scale = size / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: (100 - y) * scale) }
            path.move(to: p(8, 32))
            for point in [(92,32),(100,41),(92,50),(100,59),(92,68),(8,68),(0,59),(8,50),(0,41)] {
                path.line(to: p(CGFloat(point.0), CGFloat(point.1)))
            }
            path.close()
            for x: CGFloat in [36, 57] { path.appendRect(NSRect(x: x * scale, y: 42 * scale, width: 7 * scale, height: 16 * scale)) }
            path.windingRule = .evenOdd
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
