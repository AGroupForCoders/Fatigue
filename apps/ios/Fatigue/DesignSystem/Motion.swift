import SwiftUI

/// The app's motion, built on the duration tokens in `tokens.json`.
///
/// Every animation is a spring with no bounce. A spring starts from wherever the view is on screen,
/// so tapping again mid-animation redirects it instead of snapping back and restarting.
/// Bounce is saved for things the user throws, and the workout screen has none of those yet.
extension Animation {
    /// Press feedback and small state changes, such as a tick box filling in.
    static var quick: Animation { .smooth(duration: Tokens.Motion.quick) }

    /// Panels arriving and leaving, rows being added, and scrolling to a set.
    static var standard: Animation { .smooth(duration: Tokens.Motion.standard) }
}

extension AnyTransition {
    /// A panel pinned to the bottom edge: it rises from the edge and leaves the same way.
    /// With Reduce Motion on it only fades, so nothing slides across the screen.
    static func bottomPanel(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

/// Press feedback for compact controls: shrinks to 97% the moment a finger lands, before the tap
/// is confirmed, so the control feels like it heard you. Full-width rows dim instead of shrinking.
struct PressStyle: ButtonStyle {
    var dims = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !dims ? 0.97 : 1)
            .opacity(configuration.isPressed && dims ? 0.5 : 1)
            .animation(.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    /// Shrinks a little while pressed. For cells, boxes and buttons.
    static var press: PressStyle { PressStyle() }

    /// Dims while pressed. For full-width rows, where shrinking would look like the row is moving.
    static var pressRow: PressStyle { PressStyle(dims: true) }
}
