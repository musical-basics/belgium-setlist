import AppKit
import Carbon.HIToolbox

/// A SYSTEM-WIDE panic hotkey — **⌃⌥⌘Q** (Control-Option-Command-Q) — that quits ShowRunner
/// even when it is NOT the frontmost application.
///
/// Why this exists: the menu's Cmd-Q, the Esc/STOP key, and the "CLOSE APPLICATION" button all
/// only fire when ShowRunner is the *active* app. On show day a full-screen title card can be up
/// while focus has drifted to another app (or the borderless audience window covers the operator
/// window), and then NONE of those reach us — the app looks unkillable from the keyboard. This was
/// the lockout that forced a full computer restart.
///
/// `RegisterEventHotKey` registers the combo globally with the window server, so it fires no matter
/// which app is focused, full-screen or not. It needs NO accessibility/automation permission. The
/// combo is plain Cmd-Q plus two extra modifiers: trivial to remember, essentially impossible to hit
/// by accident, and it does NOT hijack any app's normal Cmd-Q.
final class GlobalPanicHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) { self.onFire = onFire }

    /// Returns nil on success, or a short error string for logging. Failure is non-fatal — the
    /// phone QUIT button and (when active) the menu Cmd-Q remain as the other kill paths.
    @discardableResult
    func register() -> String? {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let me = Unmanaged<GlobalPanicHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onFire() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        if installStatus != noErr { return "InstallEventHandler failed (\(installStatus))" }

        let hotKeyID = EventHotKeyID(signature: OSType(0x53524b4c) /* 'SRKL' */, id: 1)
        let mods = UInt32(controlKey | optionKey | cmdKey)
        let regStatus = RegisterEventHotKey(UInt32(kVK_ANSI_Q), mods, hotKeyID,
                                            GetApplicationEventTarget(), 0, &hotKeyRef)
        if regStatus != noErr { return "RegisterEventHotKey failed (\(regStatus))" }
        return nil
    }

    func unregister() {
        if let h = hotKeyRef { UnregisterEventHotKey(h); hotKeyRef = nil }
        if let e = handlerRef { RemoveEventHandler(e); handlerRef = nil }
    }
}
