import Carbon
import Foundation
import os.log

final class HotkeyService {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "HotkeyService")

    var onHotkeyPressed: (() -> Void)?

    static var shared: HotkeyService?

    func register() {
        HotkeyService.shared = self

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5046_4C57) // "PFLW"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async { HotkeyService.shared?.onHotkeyPressed?() }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
                                          hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        if status != noErr {
            logger.error("Failed to register hotkey: \(status)")
        } else {
            logger.info("Global hotkey Cmd+Shift+V registered")
        }
    }

    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        HotkeyService.shared = nil
    }

    deinit { unregister() }
}
