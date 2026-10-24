import SwiftUI
import UniformTypeIdentifiers

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selection = SettingsPage(rawValue: UserDefaults.standard.string(forKey: "settings.page") ?? "general") ?? .general {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: "settings.page") }
    }
    @Published var query = ""
    @Published var target: String?
    /// Changes on every request, so asking for the same card again still scrolls to it.
    @Published private(set) var request = 0
    func open(_ page: SettingsPage, card: String? = nil) { query = ""; selection = page; target = card; request += 1 }
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
    /// Display options only mean something with more than one display.
    private var showsDisplays: Bool { controller.displayChoices.count > 1 }
    private var results: [SettingsSearchEntry] {
        SettingsSearch.matches(navigation.query).filter { showsDisplays || $0.card != "Displays" }
    }

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
                // Small labels group the pages, like macOS sidebars; they don't collapse.
                let pages = SettingsPage.allCases
                ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                    if index == 0 || page.section != pages[index - 1].section {
                        if !compact {
                            Text(page.section.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(SystemStyle.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 10).padding(.top, index > 0 ? 12 : 0).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        } else if index > 0 {
                            Spacer().frame(height: 8)
                        }
                    }
                    sidebarItem(page, compact: compact)
                }
            }.padding(.horizontal, 10)
            Spacer(minLength: 16)
        }.background(.regularMaterial)
    }
    private func sidebarItem(_ page: SettingsPage, compact: Bool) -> some View {
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
                        pageHeader("Search", subtitle: "\(results.count) matching section\(results.count == 1 ? "" : "s")")
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
            .onChange(of: navigation.request) { _ in reveal(navigation.target, with: proxy) }
            // A request made before Settings first opened arrives with the initial value.
            .onAppear { reveal(navigation.target, with: proxy) }
            .onChange(of: resultIndex) { index in
                if results.indices.contains(index) { proxy.scrollTo("search." + results[index].id, anchor: .center) }
            }
        }.background(SystemStyle.background)
    }
    private func reveal(_ target: String?, with proxy: ScrollViewProxy) {
        guard let target else { return }
        DispatchQueue.main.async { proxy.scrollTo("settings." + target, anchor: .center) }
    }
    private var subtitle: String {
        switch navigation.selection {
        case .general: return "Updates, and whether Tape is arranging your windows."
        case .permissions: return "What Tape can access, and why."
        case .layout: return "Spacing, focus, widths and motion."
        case .apps: return "Which apps and windows join the strip."
        case .shortcuts: return "Move along the strip from your keyboard or trackpad."
        case .help: return "Get started, set up your Mac and find the log."
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
                    Text("Try a different search.").foregroundStyle(SystemStyle.secondary)
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
            }
            card("Tape", symbol: "rectangle.split.3x1") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Arrange windows").font(.system(size: 13, weight: .medium))
                        Text(runningStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // On arranges the strip; off pauses Tape and puts windows back where they were.
                    Toggle("Arrange windows", isOn: Binding(get: { !controller.isPaused }, set: { on in
                        if on == controller.isPaused { controller.perform(.togglePause) }
                    }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.regular)
                    .disabled(!controller.hasAccessibility || controller.isRestoring || controller.isPreview)
                }
                if let message = controller.message { Text(message).font(.caption).foregroundStyle(SystemStyle.accent).fixedSize(horizontal: false, vertical: true) }
                if !controller.hasAccessibility {
                    Button("Allow Accessibility Access…") { controller.requestAccessibility() }
                }
            }
            if showsDisplays {
                card("Displays", symbol: "display.2") {
                    ForEach(controller.displayChoices) { display in
                        HStack {
                            Toggle(display.name, isOn: Binding(get: { display.enabled }, set: { controller.setDisplayEnabled(display.id, $0) })).toggleStyle(.checkbox)
                            Spacer()
                            Text(display.windowCount == 1 ? "1 window" : "\(display.windowCount) windows").foregroundStyle(SystemStyle.secondary)
                        }
                    }
                }
            }

        case .permissions:
            card("Accessibility", symbol: "hand.raised") {
                Label(controller.hasAccessibility ? "Access is ready" : "Access is required", systemImage: controller.hasAccessibility ? "checkmark.circle.fill" : "lock")
                    .foregroundStyle(controller.hasAccessibility ? Color.green : SystemStyle.accent)
                Text("Tape moves, resizes and focuses windows. It asks for nothing else: no account, no telemetry, and window titles never reach the log.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accessibility Settings") { controller.requestAccessibility() }
                    Button("Check Again") { controller.checkPermission() }
                }
            }

        case .layout:
            card("Spacing", symbol: "arrow.left.and.right") {
                slider("Window Gap", value: $settings.gap)
                slider("Edge Gap", value: $settings.edgeGap)
            }
            card("Focus", symbol: "viewfinder") {
                Picker("Centre the focused column", selection: $settings.centering) {
                    Text("Never").tag(CenteringMode.never)
                    Text("When the strip overflows").tag(CenteringMode.overflow)
                    Text("Always").tag(CenteringMode.always)
                }.pickerStyle(.menu)
            }
            card("Widths", symbol: "rectangle.expand.vertical") {
                HStack {
                    Text("Width presets")
                    Spacer()
                    Text("⅓ → ½ → ⅔ → Full").font(.system(.body, design: .monospaced)).foregroundStyle(SystemStyle.secondary)
                }
                Toggle("Resize columns together", isOn: $settings.sharedWidths).toggleStyle(.checkbox)
                Text("A lone window fills the screen; new columns open at half width.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary)
            }
            card("Stacks and Tabs", symbol: "rectangle.stack") {
                Text("Join a window to the next column to stack it, then switch the column between a stack and tabs. Find every command under Stacks and Tabs in the Tape menu.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("Motion", symbol: "figure.walk") {
                Toggle("Move windows instantly", isOn: $settings.reduceMotion).toggleStyle(.checkbox)
                Text("Tape also follows the Mac’s Reduce Motion setting.").font(.caption).foregroundStyle(SystemStyle.secondary)
            }

        case .apps:
            card("Managed Apps", symbol: "app.badge.checkmark") {
                Picker("Manage", selection: $settings.appPolicy.manageAll) {
                    Text("All apps, with exceptions").tag(true)
                    Text("Only selected apps").tag(false)
                }.pickerStyle(.segmented).labelsHidden()
                let primary = availableApps.filter(\.isPrimary)
                // Helpers and services follow, with the ones lacking an icon of their own last.
                let others = availableApps.filter { !$0.isPrimary && $0.hasIcon } + availableApps.filter { !$0.hasIcon }
                ForEach(primary) { app in appRow(app) }
                if !others.isEmpty {
                    Text("Background and system apps").font(.caption).foregroundStyle(SystemStyle.secondary).padding(.top, 6)
                    ForEach(others) { app in appRow(app) }
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
                ForEach(controller.managedWindowChoices) { window in
                    Toggle(window.name, isOn: Binding(get: { window.managed }, set: { controller.setWindowManaged(window.id, $0) }))
                        .toggleStyle(.checkbox).disabled(controller.isPaused)
                }
                Text(controller.isPaused ? "Turn Tape on to choose open windows." : "Applies to windows open now; new windows stay outside Tape while this is on.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary)
            }

        case .shortcuts:
            card("Keyboard", symbol: "keyboard") {
                ForEach(Array(shortcutRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    HStack { Text(row.0); Spacer(); Text(row.1).font(.system(.body, design: .monospaced)).foregroundStyle(SystemStyle.secondary) }
                }
                if !controller.shortcutConflicts.isEmpty { Text("Unavailable shortcuts\n" + controller.shortcutConflicts.joined(separator: "\n")).foregroundStyle(SystemStyle.accent) }
                Text("Shortcuts use physical key positions.").font(.caption).foregroundStyle(SystemStyle.secondary)
            }
            card("Trackpad", symbol: "hand.draw") {
                Text("Hold Control–Option and scroll sideways with two fingers to browse the strip under the pointer without switching apps. Ordinary scrolling stays with your apps.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }

        case .help:
            card("Getting Started", symbol: "book") {
                step(1, "Turn Tape on", "Allow Accessibility access, then switch on Arrange Windows in General.")
                step(2, "Choose a window", "Click a window or an app in the Dock, or press Control–Option–← / →. Tape brings it into view.")
                step(3, "Browse the strip", "Hold Control–Option and scroll sideways with two fingers.")
                step(4, "Make room", "Press Control–Option–W to cycle widths, or float a window from the Tape menu.")
                Button("Show First-Run Guide", action: showGuide)
            }
            card("Mac Setup", symbol: "desktopcomputer") {
                Text("Turn off Stage Manager and automatic window tiling, and pause other window managers, so they don’t move the same windows.")
                    .font(.caption).foregroundStyle(SystemStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card("Diagnostics", symbol: "doc.text") {
                HStack {
                    Text("The log records events and errors, never window titles.").font(.caption).foregroundStyle(SystemStyle.secondary)
                    Spacer()
                    Button("Reveal Log") { NSWorkspace.shared.activateFileViewerSelecting([TapeLog.shared.url]) }
                }
                Text("macOS 13+ · Apple Silicon + Intel · MIT License").font(.caption).foregroundStyle(SystemStyle.secondary)
            }
        }
    }

    private var runningStatus: String {
        if controller.isRestoring { return "Restoring your windows…" }
        if !controller.hasAccessibility { return "Needs Accessibility access" }
        return controller.isPaused ? "Off. Your windows are where you left them." : controller.displaySummary
    }
    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
                .background(SystemStyle.text.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.caption).foregroundStyle(SystemStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func appRow(_ app: ManagedAppChoice) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon).resizable().frame(width: 24, height: 24).opacity(app.hasIcon ? 1 : 0.6)
            Toggle(app.name, isOn: Binding(get: { settings.appPolicy.manages(app.id) }, set: { settings.appPolicy.setManaged($0, bundleID: app.id); settings.appPaths[app.id] = app.path }))
                .toggleStyle(.checkbox)
            Spacer()
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
        /// Loaded once per refresh rather than on every render.
        let icon: NSImage
        /// System helpers such as Notification Center ship without an icon of their own.
        let hasIcon: Bool
        /// Dock apps and anything installed in an Applications folder; the rest are helpers and services.
        let isPrimary: Bool
        init(id: String, name: String, path: String, regular: Bool = false) {
            self.id = id; self.name = name; self.path = path
            icon = NSWorkspace.shared.icon(forFile: path)
            let info = Bundle(url: URL(fileURLWithPath: path))?.infoDictionary ?? [:]
            hasIcon = info["CFBundleIconFile"] != nil || info["CFBundleIconName"] != nil || info["CFBundleIcons"] != nil
            let folders = ["/Applications/", "/System/Applications/", NSHomeDirectory() + "/Applications/"]
            isPrimary = hasIcon && (regular || folders.contains { path.hasPrefix($0) })
        }
    }
    private func refreshApps() {
        var apps: [String: ManagedAppChoice] = [:]
        for running in NSWorkspace.shared.runningApplications where WindowDiscovery.includesApp(policy: running.activationPolicy, isOwnApp: running.processIdentifier == getpid()) {
            guard let id = running.bundleIdentifier, id != Bundle.main.bundleIdentifier, let url = running.bundleURL else { continue }
            apps[id] = ManagedAppChoice(id: id, name: running.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path,
                                        regular: running.activationPolicy == .regular)
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
