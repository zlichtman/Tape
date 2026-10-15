import SwiftUI
import UniformTypeIdentifiers

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selection = SettingsPage(rawValue: UserDefaults.standard.string(forKey: "settings.page") ?? "general") ?? .general {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: "settings.page") }
    }
    @Published var query = ""
    @Published var target: String?
    func open(_ page: SettingsPage, card: String? = nil) { query = ""; selection = page; target = card }
}

struct SettingsView: View {
    @ObservedObject var controller: TapeController
    @ObservedObject var settings: TapeSettings
    let showGuide: () -> Void
    @ObservedObject private var navigation = SettingsNavigation.shared
    @ObservedObject private var updates = UpdateService.shared
    @State private var resultIndex = 0
    @State private var searchFocused = false
    @State private var compactSearch = false
    @State private var availableApps: [ManagedAppChoice] = []
    private var results: [SettingsSearchEntry] { SettingsSearch.matches(navigation.query) }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            HStack(spacing: 0) {
                sidebar(compact: compact).frame(width: compact ? 64 : 214)
                Rectangle().fill(SystemStyle.border).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(SystemStyle.text).background(SystemStyle.background)
        .buttonStyle(.bordered).controlSize(.small)
        .background {
            Button { searchFocused = true; compactSearch = true } label: { EmptyView() }
                .keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: navigation.query) { _ in resultIndex = 0 }
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image("TapeIcon").resizable().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 9))
                if !compact { Text("Tape").font(.system(size: 15, weight: .bold)) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.top, 48).padding(.bottom, 16)
            Group {
                if compact {
                    Button { compactSearch = true; searchFocused = true } label: {
                        Image(systemName: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.plain).accessibilityLabel("Search Settings")
                        .popover(isPresented: $compactSearch) { searchField.frame(width: 240).padding(12).background(SystemStyle.surface) }
                } else { searchField }
            }.padding(.horizontal, 10).padding(.bottom, 12)
            VStack(spacing: 3) {
                ForEach(SettingsPage.allCases) { page in
                    Button { navigation.open(page); compactSearch = false; searchFocused = false } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.symbol).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(navigation.selection == page ? SystemStyle.accent : SystemStyle.secondary).frame(width: 19)
                            if !compact { Text(page.title).font(.system(size: 13, weight: navigation.selection == page ? .semibold : .medium)); Spacer(minLength: 0) }
                        }.padding(.horizontal, compact ? 0 : 10).frame(maxWidth: .infinity, minHeight: 34)
                            .contentShape(Rectangle())
                            .background(navigation.selection == page ? SystemStyle.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityLabel(page.title).help(compact ? page.title : "")
                }
            }.padding(.horizontal, 10)
            Spacer(minLength: 16)

        }.background(.regularMaterial)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(SystemStyle.secondary)
            SearchField(text: $navigation.query, focused: $searchFocused,
                        up: { resultIndex = max(0, resultIndex - 1) },
                        down: { resultIndex = min(max(0, results.count - 1), resultIndex + 1) },
                        submit: { if results.indices.contains(resultIndex) { open(results[resultIndex]) } },
                        escape: { navigation.query = ""; searchFocused = false; compactSearch = false },
                        color: .labelColor)
            if !navigation.query.isEmpty {
                Button { navigation.query = ""; navigation.target = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(SystemStyle.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear Search")
            }
        }.font(.system(size: 13)).padding(.horizontal, 12).frame(height: 34)
            .background(SystemStyle.text.opacity(searchFocused ? 0.09 : 0.06), in: Capsule())
            .overlay { Capsule().strokeBorder(searchFocused ? SystemStyle.border : .clear, lineWidth: 1) }
    }
    private func open(_ result: SettingsSearchEntry) {
        navigation.open(result.destination, card: result.card); searchFocused = false; compactSearch = false
    }

    private var detail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !navigation.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pageHeader("Search", subtitle: "\(results.count) Matching Sections")
                        searchResults
                    } else {
                        pageHeader(navigation.selection.title, subtitle: subtitle)
                        pageContent
                    }
                }.padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [SystemStyle.background, SystemStyle.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32).allowsHitTesting(false)
            }
            .onChange(of: navigation.selection) { _ in proxy.scrollTo("pageHeader", anchor: .top) }
            .onChange(of: navigation.target) { target in
                guard let target else { return }
                DispatchQueue.main.async { proxy.scrollTo("settings." + target, anchor: .center) }
            }
            .onChange(of: resultIndex) { index in
                if results.indices.contains(index) { proxy.scrollTo("search." + results[index].id, anchor: .center) }
            }
        }.background(SystemStyle.background)
    }
    private var subtitle: String {
        switch navigation.selection {
        case .general: return "Keep Tape Ready And Up To Date."
        case .apps: return "Choose which apps belong on your strip."
        case .layout: return "Make Room For The Way You Work."
        case .shortcuts: return "Move Along The Strip From Your Keyboard Or Trackpad."
        case .permissions: return "See What Tape Can Access, And Why."
        case .help: return "Get Started And Keep Your Windows In Reach."
        }
    }
    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(SystemStyle.secondary)
        }.padding(.bottom, 2).id("pageHeader")
    }
    private var searchResults: some View {
        VStack(spacing: 6) {
            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(SystemStyle.secondary)
                    Text("No Results").font(.headline)
                    Text("Try A Different Search.").foregroundStyle(SystemStyle.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Button { open(result) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: result.destination.symbol).foregroundStyle(SystemStyle.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.card).font(.system(size: 14, weight: .semibold))
                            Text(result.destination.title).font(.caption).foregroundStyle(SystemStyle.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(SystemStyle.secondary)
                    }.padding(12).contentShape(Rectangle())
                        .background(index == resultIndex ? SystemStyle.selected : SystemStyle.surface, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).id("search." + result.id)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch navigation.selection {
        case .general:
            card("Tape", symbol: "rectangle.split.3x1") {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(controller.isPaused ? "Tape Is Paused" : "Tape Is Running").font(.headline)
                        Text(controller.isRestoring ? "Restoring your windows…" : controller.displaySummary).foregroundStyle(SystemStyle.secondary)
                    }
                    Spacer()
                    Button(controller.isPaused ? "Start Tape" : "Pause and restore windows") { controller.perform(.togglePause) }
                        .disabled(!controller.hasAccessibility || controller.isRestoring || controller.isPreview)
                }
                if let message = controller.message { Text(message).foregroundStyle(SystemStyle.accent).fixedSize(horizontal: false, vertical: true) }
                Text("Click an app in the Dock or use the Tape menu to choose a window. Tape brings it into view. Use the menu’s Width commands to make room.").foregroundStyle(SystemStyle.secondary)
            }
            card("Displays", symbol: "display.2") {
                ForEach(controller.displayChoices) { display in
                    HStack {
                        Toggle(display.name, isOn: Binding(get: { display.enabled }, set: { controller.setDisplayEnabled(display.id, $0) })).toggleStyle(.checkbox)
                        Spacer()
                        Text("\(display.windowCount) windows").foregroundStyle(SystemStyle.secondary)
                    }
                }
                Text("Scroll the display under your pointer with Control–Option. Keyboard navigation follows the focused window. Disabled displays are left alone.").font(.callout).foregroundStyle(SystemStyle.secondary)
            }
            card("Updates", symbol: "arrow.triangle.2.circlepath") {
                HStack(spacing: 12) {
                    Image("TapeIcon").resizable().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tape \(installedVersion)").font(.system(size: 14, weight: .semibold))
                        Text(updates.status == .idle ? "Stable release" : updates.status.label)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updates.actionLabel) { updates.performPrimaryAction() }
                        .buttonStyle(.bordered).controlSize(.small).disabled(updates.isBusy)
                }
                Divider()
                Toggle("Check automatically", isOn: $updates.automaticallyCheckForUpdates).toggleStyle(.checkbox)
                if updates.automaticallyCheckForUpdates {
                    Toggle("Download updates when available", isOn: $updates.automaticallyInstallUpdates).toggleStyle(.checkbox)
                }
                Text("Updates come from GitHub and are signature-verified. Tape asks before restarting to install.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .apps:
            card("Managed Apps", symbol: "app.badge.checkmark") {
                Picker("Manage", selection: $settings.appPolicy.manageAll) {
                    Text("All apps, with exceptions").tag(true)
                    Text("Only selected apps").tag(false)
                }.pickerStyle(.segmented)
                Text("Checked apps join Tape. Unchecking an app puts its windows back and leaves them alone. Dialogs and full-screen windows always stay outside the strip.").foregroundStyle(.secondary)
                ForEach(availableApps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 24, height: 24)
                        Toggle(app.name, isOn: Binding(get: { settings.appPolicy.manages(app.id) }, set: { settings.appPolicy.setManaged($0, bundleID: app.id); settings.appPaths[app.id] = app.path }))
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                }
                if availableApps.isEmpty { Text("Open an app or add it below.").foregroundStyle(.secondary) }
                HStack {
                    Button("Add App…") { addApp() }
                    Button("Refresh Open Apps") { refreshApps() }
                }
            }.onAppear { refreshApps() }
            card("Managed Windows", symbol: "rectangle.on.rectangle") {
                Toggle("Manage only checked windows", isOn: Binding(get: { !controller.manageAllWindows }, set: { controller.setManageAllWindows(!$0) }))
                    .toggleStyle(.checkbox).disabled(controller.isPaused)
                Text("Locking keeps the focused window in Tape. Check any other windows you want to include. Unchecking restores a window’s original size and position. These choices apply to currently open windows; new windows stay unmanaged while locked.").foregroundStyle(.secondary)
                ForEach(controller.managedWindowChoices) { window in
                    Toggle(window.name, isOn: Binding(get: { window.managed }, set: { controller.setWindowManaged(window.id, $0) }))
                        .toggleStyle(.checkbox).disabled(controller.isPaused)
                }
                if controller.isPaused { Text("Start Tape to choose open windows.").foregroundStyle(.secondary) }
            }
        case .layout:
            card("Spacing", symbol: "arrow.left.and.right") {
                slider("Window Gap", value: $settings.gap)
                slider("Edge Gap", value: $settings.edgeGap)
                Text("The Dock and menu bar stay clear. Both gaps can be zero.").foregroundStyle(SystemStyle.secondary)
            }
            card("Focus", symbol: "viewfinder") {
                Picker("Centre The Focused Column", selection: $settings.centering) {
                    Text("Never").tag(CenteringMode.never)
                    Text("When The Strip Overflows").tag(CenteringMode.overflow)
                    Text("Always").tag(CenteringMode.always)
                }.pickerStyle(.menu)
            }
            card("Motion", symbol: "figure.walk") {
                Toggle("Move windows instantly", isOn: $settings.reduceMotion)
                Text("Tape also follows the Mac’s Reduce Motion setting.").foregroundStyle(.secondary)
            }
            card("Widths", symbol: "rectangle.expand.vertical") {
                Text("⅓ → ½ → ⅔ → Full").font(.title3.monospaced())
                Text("A lone window fills the screen. New columns use half width; an explicit width is kept when you open app tabs. Use Width → Make All Columns This Width in the Tape menu to size a display’s strip together.").foregroundStyle(SystemStyle.secondary)
                Toggle("Resize columns together", isOn: $settings.sharedWidths).toggleStyle(.checkbox)
                Text("Share width changes from shortcuts, menu presets, and dragging a window’s edge with all columns on that display.").foregroundStyle(.secondary)
            }
            card("Stacks and Tabs", symbol: "rectangle.stack") {
                Text("Join the focused window to a neighboring column with Control–Option–, or . Switch between a vertical stack and tabs with Control–Option–T. Use the up/down arrows with Control–Option to select a window, and add Shift to reorder it.").foregroundStyle(.secondary)
                Text("Drag a title bar to reorder columns. Drag a Tape tab to reorder tabs. Separate a window with Control–Option–Shift–,. Stack height controls are in the Tape menu.").foregroundStyle(.secondary)
            }
        case .shortcuts:
            card("Keyboard", symbol: "keyboard") {
                Text("Shortcuts use physical key positions. Alternate bindings perform the same action.").foregroundStyle(SystemStyle.secondary)
                ForEach(Array(shortcutRows.enumerated()), id: \.offset) { _, row in
                    HStack { Text(row.0); Spacer(); Text(row.1).font(.system(.body, design: .monospaced)).foregroundStyle(SystemStyle.secondary) }
                    Rectangle().fill(SystemStyle.border).frame(height: 1)
                }
                if !controller.shortcutConflicts.isEmpty { Text("Unavailable Shortcuts\n" + controller.shortcutConflicts.joined(separator: "\n")).foregroundStyle(SystemStyle.accent) }
                Text("Shortcut recording will be added in a later build.").font(.callout).foregroundStyle(SystemStyle.secondary)
            }
            card("Trackpad", symbol: "hand.draw") {
                Text("Hold Control–Option before scrolling horizontally with two fingers. Tape moves the strip on the display under your pointer without switching apps. Click a window or use a focus shortcut to select it.")
                Text("Scrolling follows your Mac’s natural-scroll direction and momentum. Ordinary scrolling stays with your apps.").foregroundStyle(SystemStyle.secondary)
            }
        case .permissions:
            card("Accessibility", symbol: "hand.raised") {
                Label(controller.hasAccessibility ? "Access Is Ready" : "Access Is Required", systemImage: controller.hasAccessibility ? "checkmark.circle" : "lock").foregroundStyle(SystemStyle.accent)
                Text("Allow Tape to move, resize, and focus windows. Tape requests only Accessibility access.")
                Text("No account. No telemetry. Window titles are never written to the log.").foregroundStyle(SystemStyle.secondary)
                HStack {
                    Button("Open Accessibility Settings") { controller.requestAccessibility() }
                    Button("Check Access") { controller.checkPermission() }
                }
            }
        case .help:
            card("Getting Started", symbol: "book") {
                Text("1. Start Tape from its menu bar icon.\n2. Choose any app in the Dock, click a window, or choose Go to Window from the Tape menu.\n3. Hold Control–Option and scroll horizontally with two fingers to browse without switching apps. Set Width from the menu, or use Control–Option–W.\n4. Choose Float This Window to move a window freely.\n5. Pause Tape restores your original window positions.")
                Button("Show First-Run Guide", action: showGuide)
            }
            card("Mac Setup", symbol: "desktopcomputer") {
                Text("For predictable layouts, turn off Stage Manager and automatic tiling, and pause other window-arranging tools.")
                Text("At shared display edges, overflow windows stay on the managed display, behind the focused window.").foregroundStyle(SystemStyle.secondary)
            }
            card("Diagnostics", symbol: "doc.text") {
                Text("Pause and Quit restore the windows Tape arranged, adjusted to fit the current display.")
                Button("Reveal Log") { NSWorkspace.shared.activateFileViewerSelecting([TapeLog.shared.url]) }
                Text("macOS 13+ · Apple Silicon + Intel · MIT License").font(.caption).foregroundStyle(SystemStyle.secondary)
            }
        }
    }

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(SystemStyle.secondary)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(SystemStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(navigation.target == title ? SystemStyle.accent.opacity(0.65) : SystemStyle.border, lineWidth: navigation.target == title ? 1.5 : 1) }
            .id("settings." + title)
    }
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 105, alignment: .leading)
            Slider(value: value, in: 0...40, step: 1)
            Text("\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(SystemStyle.secondary).frame(width: 45, alignment: .trailing)
        }
    }
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    private var shortcutRows: [(String, String)] {
        var order: [TapeAction] = [], bindings: [TapeAction: [String]] = [:]
        for binding in HotKeyBinding.defaults {
            if bindings[binding.action] == nil { order.append(binding.action) }
            bindings[binding.action, default: []].append(binding.display)
        }
        return order.map { ($0.label, bindings[$0]!.joined(separator: "  /  ")) }
    }
    private struct ManagedAppChoice: Identifiable {
        let id: String
        let name: String
        let path: String
    }
    private func refreshApps() {
        var apps: [String: ManagedAppChoice] = [:]
        for running in NSWorkspace.shared.runningApplications where WindowDiscovery.includesApp(policy: running.activationPolicy, isOwnApp: running.processIdentifier == getpid()) {
            guard let id = running.bundleIdentifier, id != Bundle.main.bundleIdentifier, let url = running.bundleURL else { continue }
            apps[id] = ManagedAppChoice(id: id, name: running.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
        }
        let known = Set(settings.appPaths.keys).union(settings.appPolicy.selected).union(settings.appPolicy.excluded)
        for id in known where apps[id] == nil {
            let url = settings.appPaths[id].map { URL(fileURLWithPath: $0) } ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            guard let url else { continue }
            apps[id] = ManagedAppChoice(id: id, name: url.deletingPathExtension().lastPathComponent, path: url.path)
        }
        availableApps = apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Tape"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
                settings.appPaths[id] = url.path
                settings.appPolicy.setManaged(true, bundleID: id)
            }
            refreshApps()
        }
    }
}
