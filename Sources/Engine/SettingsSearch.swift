import Foundation

public enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    // Sidebar order; consecutive pages share a section label.
    case general, permissions, layout, apps, shortcuts, help
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var section: String {
        switch self {
        case .general, .permissions: return "Core"
        case .layout, .apps: return "Strip"
        case .shortcuts, .help: return "Reference"
        }
    }
    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .apps: return "app.badge.checkmark"
        case .layout: return "rectangle.split.3x1"
        case .shortcuts: return "keyboard"
        case .permissions: return "hand.raised"
        case .help: return "questionmark.circle"
        }
    }
}

public struct SettingsSearchEntry: Identifiable, Equatable, Sendable {
    public let destination: SettingsPage
    public let card: String
    public let keywords: String
    public var id: String { destination.rawValue + "." + card }
}

public enum SettingsSearch {
    public static let entries: [SettingsSearchEntry] = [
        .init(destination: .general, card: "Updates", keywords: "software version automatic check install download relaunch"),
        .init(destination: .general, card: "Tape", keywords: "pause resume start stop switch enable running arrange restore windows"),
        .init(destination: .general, card: "Displays", keywords: "monitors screens enable disable external independent strips send next move display"),
        .init(destination: .apps, card: "Managed Apps", keywords: "apps applications include exclude select choose tag rule float manage"),
        .init(destination: .apps, card: "Managed Windows", keywords: "lock tape individual window include exclude selected exceptions floating scope"),
        .init(destination: .layout, card: "Spacing", keywords: "window gap edge dock menu bar points zero"),
        .init(destination: .layout, card: "Focus", keywords: "centering centring centre center focused scroll overflow always never"),
        .init(destination: .layout, card: "Widths", keywords: "width presets third half two thirds full wider narrower resize all together shared drag single"),
        .init(destination: .layout, card: "Stacks and Tabs", keywords: "join detach group stack tabs reorder drag height taller shorter equal"),
        .init(destination: .shortcuts, card: "Keyboard", keywords: "hotkeys shortcut keys bindings focus move widths centre float pause physical layout"),
        .init(destination: .shortcuts, card: "Trackpad", keywords: "scroll scrolling swipe gesture two fingers horizontal momentum control option browse"),
        .init(destination: .layout, card: "Motion", keywords: "reduce motion animation accessibility instant movement"),
        .init(destination: .permissions, card: "Accessibility", keywords: "permission privacy access enable system settings"),
        .init(destination: .help, card: "Getting Started", keywords: "guide first run onboarding learn keyboard navigation"),
        .init(destination: .help, card: "Mac Setup", keywords: "stage manager tiling conflict window manager dock displays"),
        .init(destination: .help, card: "Diagnostics", keywords: "log logging troubleshoot error reveal restart restore support"),
    ]
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
    public static func matches(_ query: String) -> [SettingsSearchEntry] {
        let query = normalized(query)
        let words = query.split(separator: " ")
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let text = normalized(entry.destination.title + " " + entry.card + " " + entry.keywords)
            return words.allSatisfy { text.contains($0) }
        }.sorted {
            let a = normalized($0.card).hasPrefix(query), b = normalized($1.card).hasPrefix(query)
            if a != b { return a }
            if $0.destination != $1.destination {
                return SettingsPage.allCases.firstIndex(of: $0.destination)! < SettingsPage.allCases.firstIndex(of: $1.destination)!
            }
            return $0.card.localizedStandardCompare($1.card) == .orderedAscending
        }
    }
}
