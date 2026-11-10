import QuartzCore
import SwiftUI

/// The panel's animations and their timings, in one place.
///
/// Panel views take their animations from here instead of defining their own, so the panel
/// moves consistently and its timings can be tuned together. With the system's Reduce Motion
/// setting on, nothing slides, stretches or scales; what is left are short fades.
enum PanelMotion {
    /// How many times slower than normal the animations play.
    ///
    /// Launch with `-PanelSlowMotion 5` to watch them at a fifth of their speed.
    static let slowdown: Double = {
        let factor = UserDefaults.standard.double(forKey: "PanelSlowMotion")
        return factor >= 1 ? factor : 1
    }()

    // MARK: - Showing and hiding the panel

    /// How the panel window appears or disappears.
    struct WindowTransition {
        /// The size the panel grows from or shrinks to, as a fraction of its full size.
        let scale: CGFloat
        let duration: TimeInterval
        let timing: CAMediaTimingFunction
    }

    /// The panel fades in while growing slightly; with Reduce Motion it only fades.
    static func showTransition(reduceMotion: Bool) -> WindowTransition {
        reduceMotion
            ? WindowTransition(scale: 1, duration: 0.12 * slowdown, timing: CAMediaTimingFunction(name: .linear))
            : WindowTransition(scale: 0.96, duration: 0.17 * slowdown, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
    }

    /// The panel fades out while shrinking slightly; with Reduce Motion it only fades.
    static func hideTransition(reduceMotion: Bool) -> WindowTransition {
        reduceMotion
            ? WindowTransition(scale: 1, duration: 0.09 * slowdown, timing: CAMediaTimingFunction(name: .linear))
            : WindowTransition(scale: 0.97, duration: 0.11 * slowdown, timing: CAMediaTimingFunction(name: .easeIn))
    }

    // MARK: - Selection

    /// The selection highlight gliding to another row, and the list scrolling to keep up with it.
    /// A spring, so that holding an arrow key changes its course smoothly.
    static var selection: Animation { paced(.spring(response: 0.2, dampingFraction: 1)) }

    /// A row's text changing colour as it becomes or stops being the selected one.
    static var selectionTint: Animation { paced(.easeOut(duration: 0.11)) }

    // MARK: - Filter pills

    /// The edge of the filter fill that reaches the newly chosen pill first.
    static var filterLeadingEdge: Animation { paced(.spring(response: 0.2, dampingFraction: 0.9)) }

    /// The edge that follows, which is what makes the fill stretch and then close up.
    static var filterFollowingEdge: Animation { paced(.spring(response: 0.42, dampingFraction: 0.74)) }

    // MARK: - List changes

    /// Rows sliding to their new places after a delete, a filter change or a search.
    static var listChange: Animation { paced(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) }

    /// A new row fades in once the others have started moving; a removed row fades out, shrinking slightly.
    /// With Reduce Motion rows only fade. The transition carries its own animation, so it runs
    /// even then, when the rows around it do not slide.
    static func rowTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .asymmetric(
                insertion: .opacity.animation(paced(.easeOut(duration: 0.12))),
                removal: .opacity.animation(paced(.easeOut(duration: 0.09))))
            : .asymmetric(
                insertion: .opacity.animation(paced(.easeOut(duration: 0.18).delay(0.06))),
                removal: .opacity.combined(with: .scale(scale: 0.96)).animation(paced(.easeOut(duration: 0.14))))
    }

    // MARK: - Detail pane

    /// The buttons below the preview making room for one that appears or disappears.
    static var detailChange: Animation { paced(.easeOut(duration: 0.14)) }

    /// The preview cross-fading to another item's: the old one leaves quickly, the new one settles in.
    static var detailTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(paced(.easeOut(duration: 0.14))),
            removal: .opacity.animation(paced(.easeIn(duration: 0.09)))
        )
    }

    /// A button below the preview appearing once the others have made room for it, and leaving
    /// before they close up again, so that their labels never overlap.
    static var detailButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(paced(.easeOut(duration: 0.1).delay(0.06))),
            removal: .opacity.animation(paced(.easeIn(duration: 0.05)))
        )
    }

    // MARK: - Paste

    /// How long the pasted row stays lit before the panel closes.
    static var pasteFlashDuration: TimeInterval { 0.09 * slowdown }

    /// The pasted row lighting up.
    static var pasteFlash: Animation { paced(.linear(duration: 0.03)) }

    // MARK: - Hover and press

    /// A row's tint under the pointer.
    static var hover: Animation { paced(.easeOut(duration: 0.09)) }

    /// A control giving way under the pointer, quickly.
    static var press: Animation { paced(.easeOut(duration: 0.06)) }

    /// A control springing back on release, slightly past its size.
    static var release: Animation { paced(.spring(response: 0.28, dampingFraction: 0.5)) }

    /// How far a pill or button shrinks while pressed.
    static let controlPressScale: CGFloat = 0.92

    /// How far a row shrinks while pressed. Less than a control, because it is much wider.
    static let rowPressScale: CGFloat = 0.985

    /// How far the glass capsule around the filter pills swells while one of them is pressed.
    static let glassPressScale: CGFloat = 1.04

    private static func paced(_ animation: Animation) -> Animation {
        slowdown == 1 ? animation : animation.speed(1 / slowdown)
    }
}

extension View {
    /// Animates this view with a panel animation whenever `value` changes. Pass no animation to
    /// make the change happen at once, whatever a view further out asked for.
    ///
    /// With Reduce Motion on it uses `reduced` instead. Leave that out for anything that moves,
    /// so it jumps; pass a fade for changes that only fade.
    func panelAnimation<Value: Equatable>(_ animation: Animation?, reduced: Animation? = nil, value: Value) -> some View {
        modifier(PanelAnimationModifier(animation: animation, reduced: reduced, value: value))
    }

    /// Scales this view to `scale` while pressed and lets it spring back on release.
    /// With Reduce Motion on the view keeps its size.
    func panelPressScale(_ scale: CGFloat, isPressed: Bool) -> some View {
        modifier(PanelPressScaleModifier(scale: scale, isPressed: isPressed))
    }
}

private struct PanelAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let reduced: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? reduced : animation, value: value)
    }
}

private struct PanelPressScaleModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scale: CGFloat
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .animation(isPressed ? PanelMotion.press : PanelMotion.release, value: isPressed)
    }
}
