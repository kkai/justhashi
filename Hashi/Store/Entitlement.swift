import Foundation

/// What the one-time unlock buys. Used to give the paywall contextual copy.
nonisolated enum PaidFeature: String, CaseIterable, Sendable, Identifiable {
    case advancedLessons
    case practiceDrills
    case teachingHints
    case largeBoards
    case stats

    var id: String { rawValue }

    var headline: String {
        switch self {
        case .advancedLessons: "The rest of the curriculum"
        case .practiceDrills: "Practice drills"
        case .teachingHints: "Hints that teach"
        case .largeBoards: "Large boards"
        case .stats: "Your progress"
        }
    }

    var pitch: String {
        switch self {
        case .advancedLessons:
            "Six more lessons: One Each Way, Counting, Don't Cut Off, Stay Connected, What If and Deep Water."
        case .practiceDrills:
            "Targeted drills for every technique, with mastery tracking that knows what you've actually earned unaided."
        case .teachingHints:
            "A hint that names the technique and shows you which corridor it applies to, instead of drawing the bridge for you."
        case .largeBoards:
            "The 13×13 puzzles, where counting and connectivity start to bite. Free every weekend in the Daily."
        case .stats:
            "Best times, solve counts and your mastery path across all eight techniques."
        }
    }
}

/// Every gating decision in the app, as pure functions. Kept free of StoreKit
/// and of any actor isolation so the rules can be tested exhaustively without a
/// store connection — see `EntitlementTests`.
///
/// Every function takes `unlocked:` explicitly rather than reading a store.
/// That is what keeps them pure and `nonisolated`, and it is why the free tier
/// can be pinned by a test that never touches StoreKit.
nonisolated enum FeatureGate {

    /// Free: the rules lesson, Full Islands, and Only Neighbor. Enough to learn
    /// the game and to feel what the hint engine would be doing for you.
    static let freeLessonCeiling: Technique = .onlyNeighbor

    static func isLessonAvailable(_ technique: Technique?, unlocked: Bool) -> Bool {
        guard !unlocked else { return true }
        guard let technique else { return true }  // the rules lesson
        return technique <= freeLessonCeiling
    }

    static func isSizeAvailable(_ size: BoardSize, unlocked: Bool) -> Bool {
        unlocked || size != .large
    }

    /// Difficulty is never gated — a free player can play Hard on a small board.
    static func isDifficultyAvailable(_ difficulty: Difficulty, unlocked: Bool) -> Bool {
        true
    }

    static func isAvailable(_ feature: PaidFeature, unlocked: Bool) -> Bool {
        unlocked
    }

    // MARK: - The Daily exemption

    /// The Daily is free at every size it schedules.
    ///
    /// `DailySeed.spec` puts a `.large` board on Saturday and Sunday, and
    /// `.large` is behind the unlock. The schedule cannot move: it is shipped
    /// API, and rewriting it would rewrite every player's past and future
    /// dailies (`DailySeedTests.scheduleCoversTheWeek` pins it). So the size
    /// gate simply does not apply here — and that is the better trade anyway.
    /// A free player tasting a large board every weekend is the most
    /// persuasive advertisement the paid tier has; `shouldOfferUnlock` is
    /// where that lands.
    ///
    /// Deliberately a separate function rather than a special case folded into
    /// `isSizeAvailable`, so the exemption reads as a statement of policy.
    static func isDailyAvailable(_ day: DayKey, unlocked: Bool) -> Bool {
        true
    }

    /// True when the board just finished was a taste of something the player
    /// does not own. The weekend Daily hands a free player a large board; the
    /// moment they solve it is the best moment to make the case.
    static func shouldOfferUnlock(afterSolving size: BoardSize,
                                  wasDaily: Bool, unlocked: Bool) -> Bool {
        wasDaily && !unlocked && !isSizeAvailable(size, unlocked: unlocked)
    }
}
