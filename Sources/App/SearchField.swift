import SwiftUI
import AppKit

/// Native field delegate handles result navigation on macOS 13 as well as newer systems.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let up: () -> Void
    let down: () -> Void
    let submit: () -> Void
    let escape: () -> Void
    var color: NSColor
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search Settings"
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search Settings")
        return field
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        if view.stringValue != text { view.stringValue = text }
        view.textColor = color
        view.placeholderAttributedString = NSAttributedString(string: "Search Settings", attributes: [.foregroundColor: color.withAlphaComponent(0.6), .font: NSFont.systemFont(ofSize: 13)])
        if focused, !context.coordinator.wasFocused {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        context.coordinator.wasFocused = focused
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var wasFocused = false
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.moveUp(_:)): parent.up(); return true
            case #selector(NSResponder.moveDown(_:)): parent.down(); return true
            case #selector(NSResponder.insertNewline(_:)): parent.submit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.escape(); return true
            default: return false
            }
        }
    }
}
