import AppKit
import ApplicationServices
#if SWIFT_PACKAGE
import TapeEngine
#endif

/// Public scroll events, not undocumented multi-finger gesture events.
/// The callback performs no remote AX calls and never activates an app.
final class ScrollInput {
    var accepts: ((CGPoint) -> Bool)?
    var onScroll: ((Double, CGPoint) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = ScrollGesture()

    @discardableResult func start() -> Bool {
        stop()
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ScrollInput>.fromOpaque(context).takeUnretainedValue().receive(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { stop(); return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, let scroll = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let modifiers = flags.contains(.maskControl) && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand) && !flags.contains(.maskShift)
        let phase = scroll.phase, momentum = scroll.momentumPhase
        let consume = gesture.consume(x: scroll.scrollingDeltaX, y: scroll.scrollingDeltaY,
            precise: scroll.hasPreciseScrollingDeltas, modifiers: modifiers,
            eligible: accepts?(event.location) == true,
            begins: phase.contains(.began) || phase.contains(.mayBegin), momentum: !momentum.isEmpty,
            cancelled: phase.contains(.cancelled), finishesMomentum: momentum.contains(.ended),
            now: ProcessInfo.processInfo.systemUptime)
        guard consume else { return Unmanaged.passUnretained(event) }
        if scroll.scrollingDeltaX != 0 { onScroll?(-scroll.scrollingDeltaX, event.location) }
        return nil
    }

    func stop() {
        gesture.reset()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
    }
    deinit { stop() }
}
