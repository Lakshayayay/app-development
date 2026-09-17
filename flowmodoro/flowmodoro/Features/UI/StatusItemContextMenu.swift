import AppKit

/// MenuBarExtra has no secondary-click API, so this installs a local event
/// monitor that intercepts right-clicks on the status bar item and pops a
/// native NSMenu with a small, non-intrusive set of controls — pause/resume,
/// stop, and completing the running task — without replacing MenuBarExtra
/// with a manual NSStatusItem (see docs/ARCHITECTURE.md's Decisions log).
@MainActor
final class StatusItemContextMenu: NSObject {
    private weak var store: AppStore?
    private var monitor: Any?

    init(store: AppStore) {
        self.store = store
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window?.level == .statusBar, let store else { return event }
        NSMenu.popUpContextMenu(buildMenu(store: store), with: event, for: event.window?.contentView ?? NSView())
        return nil
    }

    private func buildMenu(store: AppStore) -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: headerTitle(store: store), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        switch store.timer.phase {
        case .idle:
            menu.addItem(action("Start", key: "s", enabled: store.settings.selectedTaskID != nil) { [weak store] in
                guard let store else { return }
                store.timer.startFocus(taskID: store.settings.selectedTaskID, mode: store.settings.selectedMode)
            })
        case .focus:
            menu.addItem(action("Pause", key: "p") { [weak store] in store?.timer.pause() })
            menu.addItem(action("Stop", key: "x") { [weak store] in store?.timer.stop() })
        case .pausedFocus:
            menu.addItem(action("Resume", key: "s") { [weak store] in store?.timer.resume() })
            menu.addItem(action("Stop", key: "x") { [weak store] in store?.timer.stop() })
        case .breakTimer:
            menu.addItem(action("Pause Break", key: "p") { [weak store] in store?.timer.pause() })
            menu.addItem(action("Skip Break", key: "") { [weak store] in store?.timer.skip() })
        case .pausedBreak:
            menu.addItem(action("Resume Break", key: "s") { [weak store] in store?.timer.resume() })
            menu.addItem(action("Skip Break", key: "") { [weak store] in store?.timer.skip() })
        case .suggestedBreak:
            menu.addItem(action("Start Break", key: "") { [weak store] in store?.timer.startSuggestedBreak() })
            menu.addItem(action("Dismiss", key: "") { [weak store] in store?.timer.reset() })
        }

        if let taskID = store.settings.selectedTaskID,
           let task = store.tasks.first(where: { $0.id == taskID }), !task.isCompleted {
            menu.addItem(.separator())
            menu.addItem(action("Complete “\(task.title)”", key: "") { [weak store] in store?.toggleTask(task) })
        }

        if store.timer.phase != .idle {
            let hidden = UserDefaults.standard.bool(forKey: "hideMenuBarTimer")
            menu.addItem(.separator())
            menu.addItem(action(hidden ? "Show Timer" : "Hide Timer", key: "h") {
                UserDefaults.standard.set(!hidden, forKey: "hideMenuBarTimer")
            })
        }

        menu.addItem(.separator())
        menu.addItem(action("Quit Flowmodora", key: "q") { NSApplication.shared.terminate(nil) })
        return menu
    }

    private func headerTitle(store: AppStore) -> String {
        switch store.timer.phase {
        case .idle:
            return "Idle"
        case .focus, .pausedFocus:
            let time = store.timer.mode == .flowmodoro
                ? formatDuration(store.timer.focusDuration(), style: .timer)
                : formatDuration(store.timer.countdownRemaining(), style: .timer)
            return "\(store.timer.phase == .pausedFocus ? "Paused" : "Focusing") · \(store.taskTitle(for: store.timer.snapshot.taskID)) · \(time)"
        case .breakTimer, .pausedBreak:
            return "\(store.timer.phase == .pausedBreak ? "Paused" : "Break") · \(formatDuration(store.timer.countdownRemaining(), style: .timer))"
        case .suggestedBreak:
            return "Break ready"
        }
    }

    /// NSMenuItem's target/action is Objective-C selector dispatch, so each
    /// item needs an NSObject target — CocoaAction bridges a plain closure to
    /// that once instead of a separate @objc method per menu action.
    private func action(_ title: String, key: String, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(CocoaAction.run), keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = [.command, .option] }
        let cocoaAction = CocoaAction(handler)
        item.target = cocoaAction
        item.representedObject = cocoaAction // keeps it alive for the menu's lifetime
        item.isEnabled = enabled
        return item
    }
}

private final class CocoaAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}
