#if os(iOS)
import UIKit
#endif

/// Haptic vocabulary: one generator per feel, prepared lazily.
///
/// Unlike `Theme` and `Motion` this must STAY `@MainActor`: `UIFeedbackGenerator`
/// is `NS_SWIFT_UI_ACTOR`, and `enabled` is mutable global state that would be a
/// hard error under `nonisolated`. Do not "fix" this for consistency.
///
/// Off iOS every method is a no-op, and the guard is `os(iOS)` rather than
/// `canImport(UIKit)` for a reason worth knowing: **UIKit imports fine on tvOS,
/// but the feedback generators do not exist there**. The looser guard sent
/// Kakuro's tvOS build into this branch and produced four "unavailable in tvOS"
/// errors while the stubs it needed sat unreachable below. `Theme` keeps
/// `canImport(UIKit)` because its UIKit path genuinely works everywhere UIKit
/// exists, so the same idiom is correct in one file and wrong in the other.
@MainActor
enum Haptics {
    static var enabled = true

    #if os(iOS)

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    /// First bridge drawn on a corridor.
    static func bridge() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.6)
    }

    /// Second bridge: the double lands a touch heavier.
    static func bridgeDouble() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.85)
    }

    /// Corridor cleared.
    static func clear() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.4)
    }

    /// An island's clue is exactly met.
    static func islandComplete() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.9)
    }

    /// Blocked move / overfill.
    static func error() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.8)
    }

    /// One hop of the win ripple (fired for the first ~3 hops only —
    /// a full-network buzz would be noise, not water).
    static func ripple() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.5)
    }

    /// Puzzle solved.
    static func win() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }

    #else

    static func bridge() {}
    static func bridgeDouble() {}
    static func clear() {}
    static func islandComplete() {}
    static func error() {}
    static func ripple() {}
    static func win() {}

    #endif
}
