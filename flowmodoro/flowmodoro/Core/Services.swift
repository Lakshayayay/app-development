import AppKit
import Combine
import Carbon.HIToolbox
import Foundation
import ServiceManagement
@preconcurrency import UserNotifications
import Observation

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func scheduleIntervalCompletion(at date: Date, title: String, body: String, sound: Bool) {
        let interval = max(1, date.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(
            identifier: "flowmodo.interval.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        center.add(request)
    }

    func cancelIntervalNotifications() {
        let center = self.center
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("flowmodo.interval.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

@MainActor
@Observable
final class LoginItemService {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
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
    private var registered = false
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
    func registerDefaultShortcuts(onStart: @escaping () -> Void, onPause: @escaping () -> Void, onStop: @escaping () -> Void) -> Bool {
        unregister()
        actions = [1: onStart, 2: onPause, 3: onStop]
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetEventDispatcherTarget(), Self.eventHandler, 1, &eventType, userData, &handlerRef) == noErr else {
            actions.removeAll()
            return false
        }

        let modifiers = UInt32(cmdKey | optionKey)
        let definitions: [(UInt32, UInt32)] = [(1, UInt32(kVK_ANSI_S)), (2, UInt32(kVK_ANSI_P)), (3, UInt32(kVK_ANSI_X))]
        for (id, keyCode) in definitions {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr, let ref else {
                unregister()
                return false
            }
            hotkeys.append(ref)
        }
        registered = true
        return true
    }

    func unregister() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        self.handlerRef = nil
        actions.removeAll()
        registered = false
    }

    var isRegistered: Bool { registered }
}

struct SyncStatus: Equatable, Sendable {
    var isConfigured = false
    var pendingChanges = 0
    var message = "Local only"
}

@MainActor
@Observable
final class LocalSyncEngine {
    private(set) var status = SyncStatus()

    func refresh(pendingChanges: Int) {
        status.pendingChanges = pendingChanges
        status.message = pendingChanges == 0 ? "Local only" : "\(pendingChanges) changes queued"
    }
}

enum AppError: LocalizedError {
    case couldNotSave

    var errorDescription: String? {
        switch self { case .couldNotSave: "Unable to save locally. Your focus data is still in memory for this session." }
    }
}
