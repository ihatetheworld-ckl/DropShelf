import Carbon
import AppKit
import Foundation

public final class HotKeyManager {
    public static let shared = HotKeyManager()

    public var onSummonShelfShortcut: (() -> Void)?
    public var onToggleAllShelvesShortcut: (() -> Void)?

    private var summonHotKeyRef: EventHotKeyRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    public func registerDefaultShortcuts() {
        unregisterAll()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    DispatchQueue.main.async {
                        if hotKeyID.id == 1 {
                            manager.onSummonShelfShortcut?()
                        } else if hotKeyID.id == 2 {
                            manager.onToggleAllShelvesShortcut?()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        // HotKey 1: Shift + Command + D (kVK_ANSI_D = 0x02) -> Summon new shelf at cursor
        let summonID = EventHotKeyID(signature: OSType(0x44534846), id: 1) // 'DSHF'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | shiftKey),
            summonID,
            GetApplicationEventTarget(),
            0,
            &summonHotKeyRef
        )

        // HotKey 2: Option + Space (kVK_Space = 0x31) -> Summon shelf / pasteboard shelf
        let toggleID = EventHotKeyID(signature: OSType(0x44534846), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey | shiftKey),
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKeyRef
        )
    }

    public func unregisterAll() {
        if let ref = summonHotKeyRef {
            UnregisterEventHotKey(ref)
            summonHotKeyRef = nil
        }
        if let ref = toggleHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
