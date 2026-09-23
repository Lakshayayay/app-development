import AppKit
import SwiftUI

struct SpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The subtle 0.97 scale gives immediate feedback on touch/click down
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            // A critically damped spring avoids bounciness but stays responsive
            .animation(.spring(response: 0.2, dampingFraction: 1.0), value: configuration.isPressed)
    }
}

extension View {
    func springButtonStyle() -> some View {
        buttonStyle(SpringButtonStyle())
    }
}

extension Animation {
    /// The single knob for every dropdown in the popover (subtask
    /// checklists, the Completed section, the Pomodoro plan card): a
    /// no-bounce spring that glides to rest instead of snapping.
    static var expandCollapse: Animation { .smooth(duration: 0.34) }
}

extension AnyTransition {
    /// Fade only, no translation — paired with `.dropdownClip()` on the
    /// container that's actually growing/shrinking. The moving edge of that
    /// container does the motion; the content underneath it just fades in
    /// or out, so it's uncovered/covered rather than sliding over whatever
    /// is below it.
    static var expandCollapse: AnyTransition { .opacity }
}

/// Toggles a dropdown's state inside one explicit animation, so the
/// dropdown itself, the rows below it, its chevron, and the popover's own
/// height all move together instead of the content fading while its
/// neighbors jump straight to their new position (the "floating text" bug).
/// Instant with Reduce Motion on.
@MainActor func withExpandCollapse(_ change: () -> Void) {
    withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .expandCollapse, change)
}

extension View {
    /// Clips to the container whose height is animating, so its content is
    /// uncovered/covered by that moving edge — the same mechanism the
    /// Pomodoro plan card's own tile already gave it "for free". 4pt of
    /// outward inset keeps a text field's focus ring from being cut off.
    func dropdownClip() -> some View { clipShape(Rectangle().inset(by: -4)) }
}
