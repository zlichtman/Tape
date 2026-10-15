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
        statusItem?.button?.toolTip = controller.isPaused ? "Tape — paused" : "Tape — \(controller.windowCountText)"
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        controller.checkPermission()
        actions.removeAll()
        menu.removeAllItems()
        let live = !controller.isPaused && !controller.isRestoring && !previewMode
        let enabled = controller.canArrange
        let column = controller.focusedColumn
        let control: NSEvent.ModifierFlags = [.control, .option]
        let shifted: NSEvent.ModifierFlags = [.control, .option, .shift]
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let home = String(UnicodeScalar(NSHomeFunctionKey)!), end = String(UnicodeScalar(NSEndFunctionKey)!)

        // Status and Pause
        item("Tape · \(controller.isPaused ? "Paused" : controller.windowCountText)", menu: menu, enabled: false) {}
        if let message = controller.message { note(message, menu: menu) }
        item(controller.isRestoring ? "Restoring Windows…" : controller.isPaused ? "Start Tape" : "Pause and Restore Windows", menu: menu,
             key: "p", modifiers: control, enabled: !controller.isRestoring && !previewMode) { [weak self] in
            guard let self else { return }
            if self.controller.hasAccessibility { self.controller.perform(.togglePause) } else { self.openGuide() }
        }
        menu.addItem(.separator())

        // Navigate
        let go = submenu("Go to Window", in: menu, enabled: enabled)
        item("Previous Column", menu: go, key: left, modifiers: control) { [weak self] in self?.controller.perform(.strip(.left)) }
        item("Next Column", menu: go, key: right, modifiers: control) { [weak self] in self?.controller.perform(.strip(.right)) }
        item("First Column", menu: go, key: home, modifiers: control) { [weak self] in self?.controller.perform(.strip(.first)) }
        item("Last Column", menu: go, key: end, modifiers: control) { [weak self] in self?.controller.perform(.strip(.last)) }
        item("Centre Focused Column", menu: go, key: "c", modifiers: control) { [weak self] in self?.controller.perform(.center) }
        go.addItem(.separator())
        for choice in controller.windowChoices {
            item(choice.name, menu: go) { [weak self] in self?.controller.chooseWindow(choice.id) }.state = choice.selected ? .on : .off
        }

        // Arrange
        item("Move Column Left", menu: menu, key: left, modifiers: shifted, enabled: enabled && (column?.index ?? 0) > 0) { [weak self] in
            self?.controller.perform(.strip(.moveLeft))
        }
        item("Move Column Right", menu: menu, key: right, modifiers: shifted,
             enabled: enabled && column.map { $0.index < $0.columnCount - 1 } == true) { [weak self] in
            self?.controller.perform(.strip(.moveRight))
        }
        let width = submenu("Width", in: menu, enabled: enabled)
        for (title, fraction) in [("One Third", 1.0 / 3), ("Half", 0.5), ("Two Thirds", 2.0 / 3), ("Full", 1.0)] {
            let preset = item(title, menu: width) { [weak self] in self?.controller.setWidth(fraction) }
            preset.state = column?.widthFraction.map { abs($0 - fraction) < 0.01 } == true ? .on : .off
        }
        width.addItem(.separator())
        item("Next Width", menu: width, key: "w", modifiers: control) { [weak self] in self?.controller.perform(.strip(.nextWidth)) }
        item("Wider", menu: width, key: "=", modifiers: control) { [weak self] in self?.controller.perform(.strip(.wider)) }
        item("Narrower", menu: width, key: "-", modifiers: control) { [weak self] in self?.controller.perform(.strip(.narrower)) }
        width.addItem(.separator())
        item("Make All Columns This Width", menu: width, enabled: (column?.columnCount ?? 0) > 1) { [weak self] in self?.controller.matchAllWidths() }
        item("Resize Columns Together", menu: width) { [weak self] in self?.controller.settings.sharedWidths.toggle() }
            .state = controller.settings.sharedWidths ? .on : .off

        let grouped = (column?.windowCount ?? 0) > 1
        let stacks = submenu("Stacks and Tabs", in: menu, enabled: enabled)
        item("Join Column on the Left", menu: stacks, key: ",", modifiers: control, enabled: (column?.index ?? 0) > 0) { [weak self] in
            self?.controller.perform(.strip(.joinLeft))
        }
        item("Join Column on the Right", menu: stacks, key: ".", modifiers: control,
             enabled: column.map { $0.index < $0.columnCount - 1 } == true) { [weak self] in
            self?.controller.perform(.strip(.joinRight))
        }
        item("Separate into Own Column", menu: stacks, key: ",", modifiers: shifted, enabled: grouped) { [weak self] in
            self?.controller.perform(.strip(.detach))
        }
        stacks.addItem(.separator())
        item(column?.tabbed == true ? "Show as Stack" : "Show as Tabs", menu: stacks, key: "t", modifiers: control, enabled: grouped) { [weak self] in
            self?.controller.perform(.strip(.toggleMode))
        }
        stacks.addItem(.separator())
        for (key, shortcut, modifiers) in [(StripActionKey.previousTab, up, control), (.nextTab, down, control),
                                           (.tabLeft, up, shifted), (.tabRight, down, shifted)] {
            item(key.label, menu: stacks, key: shortcut, modifiers: modifiers, enabled: grouped) { [weak self] in
                self?.controller.perform(.strip(key))
            }
        }
        stacks.addItem(.separator())
        let stacked = grouped && column?.tabbed == false
        for (key, shortcut, modifiers) in [(StripActionKey.taller, "=", shifted), (.shorter, "-", shifted), (.equalHeights, "", NSEvent.ModifierFlags())] {
            item(key.label, menu: stacks, key: shortcut, modifiers: modifiers, enabled: stacked) { [weak self] in
                self?.controller.perform(.strip(key))
            }
        }

        // Moving between displays only makes sense with more than one.
        let others = controller.displayChoices.filter { $0.enabled && $0.id != controller.focusedDisplayID }
        if !others.isEmpty {
            let displays = submenu("Move to Display", in: menu, enabled: controller.canSendToDisplay)
            for display in others {
                item(display.name, menu: displays) { [weak self] in self?.controller.sendWindow(to: display.id) }
            }
            displays.addItem(.separator())
            item("Next Display", menu: displays, key: "d", modifiers: control) { [weak self] in self?.controller.perform(.nextDisplay) }
        }
        let floats = controller.focusedWindowFloats
        item(floats == true ? "Tile This Window" : "Float This Window", menu: menu, key: "f", modifiers: control, enabled: floats != nil) { [weak self] in
            self?.controller.perform(.toggleFloat)
        }
        menu.addItem(.separator())

        // What Tape manages
        let scope = submenu("Managed Windows", in: menu, enabled: live)
        item("All Windows", menu: scope) { [weak self] in self?.controller.setManageAllWindows(true) }
            .state = controller.manageAllWindows ? .on : .off
        item("Only Checked Windows", menu: scope) { [weak self] in self?.controller.setManageAllWindows(false) }
            .state = controller.manageAllWindows ? .off : .on
        if !controller.managedWindowChoices.isEmpty { scope.addItem(.separator()) }
        for choice in controller.managedWindowChoices {
            item(choice.name, menu: scope) { [weak self] in self?.controller.setWindowManaged(choice.id, !choice.managed) }
                .state = choice.managed ? .on : .off
        }
        scope.addItem(.separator())
        item("Choose Apps…", menu: scope) { [weak self] in SettingsNavigation.shared.open(.apps); self?.openSettings() }
        menu.addItem(.separator())

        // App
        item("Settings…", menu: menu, key: ",", modifiers: .command) { [weak self] in self?.openSettings() }
        item("How to Use Tape…", menu: menu) { [weak self] in self?.openGuide() }
        item("Check for Updates…", menu: menu, enabled: !UpdateService.shared.isBusy) { [weak self] in
            UpdateService.shared.check(); SettingsNavigation.shared.open(.general, card: "Updates"); self?.openSettings()
        }
        menu.addItem(.separator())
        item("Quit Tape", menu: menu, key: "q", modifiers: .command) { [weak self] in self?.quit() }
    }
    private func submenu(_ title: String, in menu: NSMenu, enabled: Bool) -> NSMenu {
        let submenu = NSMenu(); submenu.autoenablesItems = false
        item(title, menu: menu, enabled: enabled) {}.submenu = submenu
        return submenu
    }
    /// Status messages can be a sentence or two; wrap them instead of stretching the menu.
    private func note(_ text: String, menu: NSMenu) {
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, line.count + word.count + 1 > 42 { lines.append(line); line = "" }
            line += line.isEmpty ? String(word) : " " + word
        }
        if !line.isEmpty { lines.append(line) }
        let entry = item(lines.joined(separator: "\n"), menu: menu, enabled: false) {}
        entry.attributedTitle = NSAttributedString(string: entry.title, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
        ])
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
