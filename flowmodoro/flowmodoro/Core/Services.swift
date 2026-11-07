import AppKit
import Carbon.HIToolbox
import Foundation
import os
import ServiceManagement
@preconcurrency import UserNotifications

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Fixed identifier (not a fresh UUID per call): scheduling with it replaces
    /// any still-pending completion notification, and cancelling is a plain
    /// synchronous removal instead of an async fetch-then-remove that could
    /// race with a new add — see docs/ARCHITECTURE.md's Decisions log.
    private static let intervalIdentifier = "flowmodo.interval"

    func scheduleIntervalCompletion(at date: Date, title: String, body: String, sound: Bool) {
        let interval = max(1, date.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(
            identifier: Self.intervalIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request)
    }

    func cancelIntervalNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.intervalIdentifier])
    }
}

/// Plays directly rather than via UNNotificationSound so the break cue still
/// lands under a Focus mode — which is exactly when a break ends.
@MainActor
enum SoundService {
    private static let logger = Logger(subsystem: "lakshayorg.flowmodoro", category: "alarm")
    private static var alarmTask: Task<Void, Never>?
    private static let alarmSound = NSSound(named: "Glass")

    static func playBell() { NSSound(named: "Glass")?.play() }

    static func startAlarm() {
        if alarmTask != nil { stopAlarm(reason: "replaced") }
        logger.debug("alarm start")
        alarmTask = Task { @MainActor in
            for ring in 0..<7 {
                guard !Task.isCancelled else { return }
                // NSSound(named:) is shared. Stop before every play so a
                // still-ringing Glass sound never drops a repeat.
                alarmSound?.stop()
                alarmSound?.volume = 1.0
                alarmSound?.play()
                logger.debug("alarm ring \(ring + 1, privacy: .public)")
                try? await Task.sleep(for: .seconds(ring == 6 ? 1 : 1.5))
            }
            guard !Task.isCancelled else { return }
            alarmSound?.stop()
            alarmTask = nil
            logger.debug("alarm stop (timeout)")
        }
    }

    static func stopAlarm() {
        stopAlarm(reason: "acknowledged")
    }

    private static func stopAlarm(reason: String) {
        guard alarmTask != nil else { return }
        alarmTask?.cancel()
        alarmTask = nil
        alarmSound?.stop()
        logger.debug("alarm stop (\(reason, privacy: .public))")
    }
}

@MainActor
final class LoginItemService {
    // The app's deployment target is macOS 26.5, so SMAppService.mainApp is
    // always available — no #available check needed.
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Carbon's RegisterEventHotKey API is used because a global monitor only observes events;
/// it cannot register a shortcut. The service intentionally keeps the platform bridge isolated.
@MainActor
final class GlobalHotkeyService {
    private var hotkeys: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    private static let signature: OSType = 0x464D4F44
    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(kEventParamDirectObject),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        Task { @MainActor in service.actions[hotKeyID.id]?() }
        return noErr
    }

    @discardableResult
    func registerDefaultShortcuts(onStart: @escaping () -> Void, onPause: @escaping () -> Void, onStop: @escaping () -> Void, onToggleTimer: @escaping () -> Void) -> Bool {
        unregister()
        actions = [1: onStart, 2: onPause, 3: onStop, 4: onToggleTimer]
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetEventDispatcherTarget(), Self.eventHandler, 1, &eventType, userData, &handlerRef) == noErr else {
            actions.removeAll()
            return false
        }

        let modifiers = UInt32(cmdKey | optionKey)
        let definitions: [(UInt32, UInt32)] = [(1, UInt32(kVK_ANSI_S)), (2, UInt32(kVK_ANSI_P)), (3, UInt32(kVK_ANSI_X)), (4, UInt32(kVK_ANSI_H))]
        for (id, keyCode) in definitions {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref else {
                unregister()
                return false
            }
            hotkeys.append(ref)
        }
        return true
    }

    func unregister() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        self.handlerRef = nil
        actions.removeAll()
    }
}

enum AppError: LocalizedError {
    case couldNotSave

    var errorDescription: String? {
        switch self { case .couldNotSave: "Unable to save locally. Your focus data is still in memory for this session." }
    }
}
