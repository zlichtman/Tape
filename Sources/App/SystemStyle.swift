import SwiftUI

/// Dynamic system colors follow macOS appearance and accessibility preferences.
enum SystemStyle {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let text = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.accentColor
    static let border = Color(nsColor: .separatorColor)
    static let selected = Color.accentColor.opacity(0.15)
}
