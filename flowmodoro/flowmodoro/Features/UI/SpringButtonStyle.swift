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
