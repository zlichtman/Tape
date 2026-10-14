import Carbon
#if SWIFT_PACKAGE
import TapeEngine
#endif

enum TapeAction: Hashable {
    case strip(StripActionKey), center, toggleFloat, togglePause, nextDisplay
    var label: String {
        switch self {
        case .strip(let key): return key.label
        case .center: return "Centre The Focused Column"
        case .toggleFloat: return "Float / Tile The Window"
        case .togglePause: return "Pause / Resume Tape"
        case .nextDisplay: return "Move To Next Display"
        }
    }
}

enum StripActionKey: Hashable {
    case left, right, first, last, slot(Int), moveLeft, moveRight, nextWidth, wider, narrower
    case joinLeft, joinRight, detach, toggleMode, previousTab, nextTab, tabLeft, tabRight, equalHeights, taller, shorter
    var changesFocus: Bool {
        switch self {
        case .left, .right, .first, .last, .slot, .previousTab, .nextTab: return true
        default: return false
        }
    }
    var action: StripAction {
        switch self {
        case .left: return .focus(.left)
        case .right: return .focus(.right)
        case .first: return .focus(.first)
        case .last: return .focus(.last)
        case .slot(let index): return .focus(.slot(index))
        case .moveLeft: return .move(-1)
        case .moveRight: return .move(1)
        case .nextWidth: return .nextWidth
        case .wider: return .adjustWidth(0.05)
        case .narrower: return .adjustWidth(-0.05)
        case .joinLeft: return .join(-1)
        case .joinRight: return .join(1)
        case .detach: return .detach
        case .toggleMode: return .toggleColumnMode
        case .previousTab: return .focusInColumn(-1)
        case .nextTab: return .focusInColumn(1)
        case .tabLeft: return .moveInColumn(-1)
        case .tabRight: return .moveInColumn(1)
        case .equalHeights: return .equalHeights
        case .taller: return .adjustHeight(0.25)
        case .shorter: return .adjustHeight(-0.25)
        }
    }
    var label: String {
        switch self {
        case .left: return "Focus Left"
        case .right: return "Focus Right"
        case .first: return "Focus First"
        case .last: return "Focus Last"
        case .slot(let index): return "Focus Column \(index + 1)"
        case .moveLeft: return "Move Left"
        case .moveRight: return "Move Right"
        case .nextWidth: return "Next Width Preset"
        case .wider: return "Wider"
        case .narrower: return "Narrower"
        case .joinLeft: return "Join Column On The Left"
        case .joinRight: return "Join Column On The Right"
        case .detach: return "Separate Into A Column"
        case .toggleMode: return "Stack / Tabs"
        case .previousTab: return "Previous Window In Column"
        case .nextTab: return "Next Window In Column"
        case .tabLeft: return "Move Tab / Stack Up"
        case .tabRight: return "Move Tab / Stack Down"
        case .equalHeights: return "Equal Stack Heights"
        case .taller: return "Taller In Stack"
        case .shorter: return "Shorter In Stack"
        }
    }
}

struct HotKeyBinding {
    let action: TapeAction
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String

    // Physical key codes; the shortcut does not depend on text input or the keyboard layout.
    static let defaults: [HotKeyBinding] = {
        let mods = UInt32(controlKey | optionKey)
        let shift = mods | UInt32(shiftKey)
        var keys: [HotKeyBinding] = []
        func add(_ action: TapeAction, _ code: Int, _ text: String, shifted: Bool = false) {
            keys.append(HotKeyBinding(action: action, keyCode: UInt32(code), modifiers: shifted ? shift : mods,
                                      display: "⌃⌥" + (shifted ? "⇧" : "") + text))
        }
        add(.strip(.left), kVK_LeftArrow, "←"); add(.strip(.left), kVK_ANSI_H, "H")
        add(.strip(.right), kVK_RightArrow, "→"); add(.strip(.right), kVK_ANSI_L, "L")
        add(.strip(.first), kVK_Home, "Home"); add(.strip(.last), kVK_End, "End")
        add(.strip(.first), kVK_ANSI_LeftBracket, "["); add(.strip(.last), kVK_ANSI_RightBracket, "]")
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, key) in digits.enumerated() { add(.strip(.slot(index)), key, String(index + 1)) }
        add(.strip(.moveLeft), kVK_LeftArrow, "←", shifted: true)
        add(.strip(.moveRight), kVK_RightArrow, "→", shifted: true)
        add(.strip(.nextWidth), kVK_ANSI_W, "W")
        add(.strip(.joinLeft), kVK_ANSI_Comma, ",")
        add(.strip(.joinRight), kVK_ANSI_Period, ".")
        add(.strip(.detach), kVK_ANSI_Comma, ",", shifted: true)
        add(.strip(.toggleMode), kVK_ANSI_T, "T")
        add(.strip(.previousTab), kVK_UpArrow, "↑")
        add(.strip(.nextTab), kVK_DownArrow, "↓")
        add(.strip(.tabLeft), kVK_UpArrow, "↑", shifted: true)
        add(.strip(.tabRight), kVK_DownArrow, "↓", shifted: true)
        add(.strip(.taller), kVK_ANSI_Equal, "=", shifted: true)
        add(.strip(.shorter), kVK_ANSI_Minus, "−", shifted: true)
        add(.strip(.wider), kVK_ANSI_Equal, "="); add(.strip(.narrower), kVK_ANSI_Minus, "−")
        add(.nextDisplay, kVK_ANSI_D, "D")
        add(.center, kVK_ANSI_C, "C"); add(.toggleFloat, kVK_ANSI_F, "F")
        add(.togglePause, kVK_ANSI_P, "P")
        return keys
    }()
}

final class HotKeys {
    var onAction: ((TapeAction) -> Void)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: TapeAction] = [:]

    func register() -> [String] {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x54415045, let action = owner.actions[id.id] else {
                return OSStatus(eventNotHandledErr)
            }
            owner.onAction?(action)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return ["Keyboard shortcuts could not be registered."] }
        var failures: [String] = []
        for (index, binding) in HotKeyBinding.defaults.enumerated() {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
                                             EventHotKeyID(signature: 0x54415045, id: id), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                references.append(reference)
                actions[id] = binding.action
            } else { failures.append("\(binding.display): \(binding.action.label)") }
        }
        return failures
    }
    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        actions.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
    deinit { unregister() }
}
