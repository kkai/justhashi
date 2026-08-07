import SwiftUI

/// Named motion tokens — views never use inline animation values.
///
/// `nonisolated` for the same reason as `Theme`: under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` these would be MainActor-isolated
/// statics read during off-main render passes. Nothing here is implicated in the
/// crash `Theme` caused — no closure escapes to UIKit — but every member is a
/// `Sendable` value type, so this costs nothing and keeps the design tokens
/// uniformly safe to read from any isolation domain.
nonisolated enum Motion {
    /// A bridge stroke drawing in from the origin island.
    static let bridgeDraw = Animation.spring(response: 0.32, dampingFraction: 0.85)
    /// Single → double: the two strokes part from the center.
    static let bridgeSplit = Animation.spring(response: 0.28, dampingFraction: 0.8)
    /// Clearing a corridor: quick fade + retract.
    static let bridgeClear = Animation.easeOut(duration: 0.18)
    /// A satisfied island settles: ring closes, disc scales 1.06 → 1.
    static let islandSettle = Animation.spring(response: 0.35, dampingFraction: 0.65)
    /// Blocked-move wiggle.
    static let reject = Animation.spring(response: 0.18, dampingFraction: 0.45)
    /// Selection and corridor-glow changes.
    static let selection = Animation.spring(response: 0.28, dampingFraction: 0.85)
    /// Win: the connectivity ripple, one hop per graph-distance step.
    static let ripple = Animation.easeOut(duration: 0.4)
    static let rippleStagger: TimeInterval = 0.055
    /// The vermillion seal thumping onto the win card.
    static let stamp = Animation.spring(response: 0.4, dampingFraction: 0.55)
    /// Board entrance: islands surface center-out.
    static let boardEntrance = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let boardEntranceStagger: TimeInterval = 0.02
    /// Hint highlight pulse.
    static let hintPulse = Animation.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true)
    /// Sheet/overlay transitions.
    static let overlay = Animation.spring(response: 0.35, dampingFraction: 0.9)
}
