# Flowmodora: UI/UX & Frontend Master Plan

Provide this document directly to your agent. It serves as the definitive architectural blueprint, design system guide, and step-by-step execution framework for building the Flowmodora application.

## Goal Description
Build the frontend and UI/UX for **Flowmodora** (a focus and productivity timer). The UI must perfectly mimic Apple's "Liquid Glass" (Glassmorphism) aesthetic without relying on bulky third-party UI kits. The architecture must be highly decoupled (pluggable), allowing the exact same UI components to be rendered seamlessly as a macOS Menu Bar app or a standalone standard macOS/iOS application window.

## Core Technologies & Exact Libraries

Apple's native tools are powerful enough to achieve this without third-party design bloat. The agent must strictly adhere to the following stack:

*   **Language:** Swift 5.10+
*   **Framework:** SwiftUI (Declarative UI is mandatory for cross-platform pluggability).
*   **State Management:** `@Observable` macro (Introduced in macOS 14 / iOS 17). Do not use the legacy `ObservableObject`.
*   **Iconography:** SF Symbols 5. 
*   **External Dependency (Highly Recommended for macOS):**
    *   **[LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)** (by Sindre Sorhus): Essential for macOS menu bar apps to provide the "Start at Login" toggle in settings.

## UI/UX Design System: "Liquid Glass"

The agent must NOT use custom transparency hacks. It must use Apple's native Material system to ensure dynamic lighting and Light/Dark mode compatibility.

1.  **The Glass Effect (Materials):**
    *   Apply `.background(.ultraThinMaterial)` or `.background(.regularMaterial)` to primary containers, cards, and popovers.
    *   This forces the OS to sample the background, apply a gaussian blur, and handle color diffusion natively.
2.  **Vibrancy (Text & Icons):**
    *   Apply `.foregroundStyle(.secondary)` or `.foregroundStyle(.tertiary)` to text. 
    *   *Why:* In SwiftUI, when secondary foreground styles are placed over a Material, Apple automatically applies **Vibrancy**, pulling the background colors through the text for a premium look.
3.  **Glass Edges (Borders):**
    *   Glass requires a reflective edge to look physical. The agent must apply a subtle border to glass containers:
    *   `.overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 0.5))`
4.  **Shadows:**
    *   Use `.shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)` behind the material to lift it off the background.

## Application Architecture (Pluggable UI)

To make the app pluggable into both a Menu Bar and a Window, the agent must completely decouple the View logic from the App lifecycle.

### 1. The Core View (`FlowmodoraTimerView.swift`)
This is a standalone SwiftUI view. It assumes nothing about where it is being rendered (Window vs. Menu Bar). It only reads from the `@Observable TimerManager`.

### 2. The Pluggable App Entry (`FlowmodoraApp.swift`)
The agent will utilize SwiftUI's modern App structure to inject the view into either environment:

```swift
@main
struct FlowmodoraApp: App {
    @State private var timerManager = TimerManager()
    
    var body: some Scene {
        // PLUG 1: Standard Application Window
        WindowGroup {
            FlowmodoraTimerView()
                .environment(timerManager)
        }
        .windowStyle(.hiddenTitleBar) // Clean, glass look for main window
        
        // PLUG 2: Menu Bar Extra (macOS only)
        #if os(macOS)
        MenuBarExtra("Flowmodora", systemImage: "timer") {
            FlowmodoraTimerView()
                .environment(timerManager)
        }
        .menuBarExtraStyle(.window) // Allows full SwiftUI views in the menu bar drop-down
        #endif
    }
}
```

## Step-by-Step Execution Plan for the Agent

The agent should execute the following steps in order:

### Phase 1: Data & State Foundation
1.  Create `TimerManager.swift` using the `@Observable` macro. 
2.  Implement properties for `timeRemaining` (Int), `currentState` (enum: focus, shortBreak, longBreak), and `isActive` (Bool).
3.  Implement the countdown logic using a `Timer` or `Task` loop with `Task.sleep`.

### Phase 2: Design System Modifiers
1.  Create a reusable `ViewModifier` called `LiquidGlassModifier.swift`.
2.  This modifier should encapsulate the `.ultraThinMaterial` background, the `.white.opacity(0.2)` stroke overlay, and the drop shadow.
3.  Create an extension on `View` (`func liquidGlassStyle() -> some View`) so it can be applied instantly to any component.

### Phase 3: UI Construction
1.  Create `FlowmodoraTimerView.swift`.
2.  Build a circular progress indicator using a `Circle().trim(from: 0, to: progress)`.
3.  Layer the time text directly in the center using a heavy, monospaced font: `.font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())`.
4.  Build the Play/Pause and Skip buttons using SF Symbols inside small, circular liquid glass capsules.

### Phase 4: Pluggable Integration & App Setup
1.  Update `App.swift` (or the `main` entry point) to include both the `WindowGroup` and the `MenuBarExtra`.
2.  Ensure the environment object (`TimerManager`) is successfully injected into both so the state remains perfectly synced whether the user looks at the window or the menu bar.

> [!IMPORTANT]  
> **Agent Directive:** Do not attempt to use `NSVisualEffectView` manually in AppKit. Stay purely in SwiftUI using `.ultraThinMaterial` and `.menuBarExtraStyle(.window)`. This ensures maximum compatibility and less code.

## Verification Plan
1. **Build & Run**: The agent will compile the project using `xcodebuild` or the Xcode IDE to ensure there are no SwiftUI syntax errors.
2. **Visual Verification**: The agent should launch the app and confirm that clicking the Menu Bar icon drops down the exact same UI as the standalone window, with synced timer states.
