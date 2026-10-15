import SwiftUI
#if SWIFT_PACKAGE
import TapeEngine
#endif

final class TapeSettings: ObservableObject {
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "gap") } }
    @Published var edgeGap: Double { didSet { defaults.set(edgeGap, forKey: "edgeGap") } }
    @Published var centering: CenteringMode { didSet { defaults.set(centering.rawValue, forKey: "centering") } }
    @Published var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "reduceMotion") } }
    @Published var sharedWidths: Bool { didSet { defaults.set(sharedWidths, forKey: "layout.sharedWidths") } }
    @Published var appPolicy: AppPolicy { didSet { defaults.set(try? JSONEncoder().encode(appPolicy), forKey: "apps.policy") } }
    @Published var appPaths: [String: String] { didSet { defaults.set(appPaths, forKey: "apps.paths") } }
    @Published var disabledDisplays: Set<String> { didSet { defaults.set(Array(disabledDisplays).sorted(), forKey: "displays.disabled") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        disabledDisplays = Set(defaults.stringArray(forKey: "displays.disabled") ?? [])
        gap = defaults.object(forKey: "gap") as? Double ?? 8
        edgeGap = defaults.object(forKey: "edgeGap") as? Double ?? 8
        centering = CenteringMode(rawValue: defaults.string(forKey: "centering") ?? "never") ?? .never
        reduceMotion = defaults.object(forKey: "reduceMotion") as? Bool ?? defaults.bool(forKey: "theme.reduceMotion")
        sharedWidths = defaults.bool(forKey: "layout.sharedWidths")
        appPolicy = defaults.data(forKey: "apps.policy").flatMap { try? JSONDecoder().decode(AppPolicy.self, from: $0) } ?? AppPolicy()
        appPaths = defaults.dictionary(forKey: "apps.paths") as? [String: String] ?? [:]
    }
    var layout: LayoutOptions { LayoutOptions(gap: gap, edgeGap: edgeGap, centering: centering) }
}
