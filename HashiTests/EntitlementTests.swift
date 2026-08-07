import Foundation
import Testing
@testable import Hashi

@Suite("Feature gate")
struct FeatureGateTests {

    /// The free tier is exactly: the rules lesson, Full Islands, Only Neighbor.
    /// Built by filtering the whole universe and compared to a literal, so
    /// "simplifying" the gate later — or adding a technique to the curriculum
    /// without deciding its tier — fails here rather than in the App Store.
    @Test func freeLessonsAreExactlyTheFirstTwo() {
        let free = ([nil] + Technique.allCases.map { Optional($0) })
            .filter { FeatureGate.isLessonAvailable($0, unlocked: false) }
        #expect(free == [nil, .fullIsland, .onlyNeighbor])
    }

    @Test func unlockingOpensEveryLesson() {
        for technique in [nil] + Technique.allCases.map({ Optional($0) }) {
            #expect(FeatureGate.isLessonAvailable(technique, unlocked: true))
        }
    }

    @Test func onlyLargeBoardsArePaid() {
        for size in BoardSize.allCases {
            #expect(FeatureGate.isSizeAvailable(size, unlocked: false) == (size != .large))
            #expect(FeatureGate.isSizeAvailable(size, unlocked: true))
        }
    }

    @Test func difficultyIsNeverPaid() {
        for difficulty in Difficulty.allCases {
            #expect(FeatureGate.isDifficultyAvailable(difficulty, unlocked: false))
            #expect(FeatureGate.isDifficultyAvailable(difficulty, unlocked: true))
        }
    }

    @Test func everyPaidFeatureNeedsTheUnlock() {
        for feature in PaidFeature.allCases {
            #expect(!FeatureGate.isAvailable(feature, unlocked: false))
            #expect(FeatureGate.isAvailable(feature, unlocked: true))
        }
    }

    /// The Daily is free at every size it schedules, including the `.large`
    /// weekend boards that are otherwise behind the unlock.
    ///
    /// The `largeDays` count is what keeps this honest: if the schedule ever
    /// stops scheduling large boards, the exemption is no longer doing any work
    /// and this fails loudly instead of passing vacuously.
    @Test func theDailyIsFreeAtEverySizeItSchedules() {
        var day = DayKey(year: 2026, month: 1, day: 1)
        var largeDays = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        for _ in 0..<371 {
            #expect(FeatureGate.isDailyAvailable(day, unlocked: false),
                    "\(day.isoString) is gated")
            if DailySeed.spec(for: day).size == .large {
                largeDays += 1
                // The exemption is doing real work here, not merely agreeing
                // with the size gate.
                #expect(!FeatureGate.isSizeAvailable(.large, unlocked: false))
            }
            let next = calendar.date(byAdding: .day, value: 1, to: day.date(calendar: calendar))!
            day = DayKey(date: next, calendar: calendar)
        }
        #expect(largeDays >= 100,
                "the weekend large boards are gone, so the Daily exemption is untested")
    }

    /// Binds the real schedule to the real funnel, rather than hand-picking
    /// `.large`: whatever `DailySeed` actually serves on a weekend, a free
    /// player must be able to play it, and must be offered the unlock after.
    ///
    /// This is the case a simulator run cannot reach without moving the host
    /// clock, so it is pinned here instead.
    @Test func aFreePlayerCanPlayTheWeekendDailyAndIsOfferedTheUnlock() {
        // 2026-08-08 is a Saturday, 2026-08-09 a Sunday.
        for day in [DayKey(year: 2026, month: 8, day: 8),
                    DayKey(year: 2026, month: 8, day: 9)] {
            let spec = DailySeed.spec(for: day)
            #expect(spec.size == .large, "\(day.isoString) is no longer a large board")
            #expect(FeatureGate.isDailyAvailable(day, unlocked: false),
                    "a free player cannot open the weekend Daily")
            #expect(!FeatureGate.isSizeAvailable(spec.size, unlocked: false),
                    "the board they just played is not actually gated elsewhere")
            #expect(FeatureGate.shouldOfferUnlock(afterSolving: spec.size,
                                                  wasDaily: true, unlocked: false),
                    "solving it should make the case for large boards")
        }
        // A weekday Daily is a size they already own, so no offer.
        let weekday = DayKey(year: 2026, month: 8, day: 10)   // Monday
        let spec = DailySeed.spec(for: weekday)
        #expect(FeatureGate.isSizeAvailable(spec.size, unlocked: false))
        #expect(!FeatureGate.shouldOfferUnlock(afterSolving: spec.size,
                                               wasDaily: true, unlocked: false))
    }

    /// The funnel: solving a weekend Daily is the moment to make the case for
    /// large boards, and the only moment.
    @Test func theWeekendDailyIsTheLargeBoardFunnel() {
        #expect(FeatureGate.shouldOfferUnlock(afterSolving: .large, wasDaily: true, unlocked: false))
        // Already paid — nothing to sell.
        #expect(!FeatureGate.shouldOfferUnlock(afterSolving: .large, wasDaily: true, unlocked: true))
        // Not a daily: a free player cannot have reached a large board any
        // other way, so this would be unreachable — and asking after an
        // ordinary win would be nagging.
        #expect(!FeatureGate.shouldOfferUnlock(afterSolving: .large, wasDaily: false, unlocked: false))
        // A size they already own is not a taste of anything.
        #expect(!FeatureGate.shouldOfferUnlock(afterSolving: .medium, wasDaily: true, unlocked: false))
        #expect(!FeatureGate.shouldOfferUnlock(afterSolving: .small, wasDaily: true, unlocked: false))
    }
}

/// One scratch suite per test, so no two tests can see each other's cache.
private func scratchDefaults(_ name: String) -> UserDefaults {
    let suite = "hashi.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let cacheKey = "hashi.entitlement.v1"

@Suite("Entitlement cache")
@MainActor
struct EntitlementCacheTests {

    /// Deliberately **not** async: there is no `await` anywhere in this test,
    /// which is the whole point. The cached flag has to be readable before the
    /// first suspension or a paying customer sees locks on frame one — and
    /// `HomeView`'s picker restoration depends on exactly that.
    @Test func cachedUnlockAppliesSynchronouslyAtInit() {
        let defaults = scratchDefaults("cached")
        defaults.set(true, forKey: cacheKey)
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: nil))
        #expect(store.isUnlocked)
    }

    /// A refund, a family revoke or a different Apple Account must take the
    /// unlock away — and rewrite the cache, or the next launch would restore it.
    @Test func completedEnumerationDowngradesAndRewritesCache() async {
        let defaults = scratchDefaults("downgrade")
        defaults.set(true, forKey: cacheKey)
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: false))
        await store.refresh()
        #expect(!store.isUnlocked)
        #expect(!defaults.bool(forKey: cacheKey))
    }

    /// `nil` means "could not determine". It must never downgrade.
    @Test func indeterminateAnswerKeepsTheCachedUnlock() async {
        let defaults = scratchDefaults("indeterminate")
        defaults.set(true, forKey: cacheKey)
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: nil))
        await store.refresh()
        #expect(store.isUnlocked)
        #expect(defaults.bool(forKey: cacheKey))
    }

    @Test func purchaseIsPickedUpByRefresh() async {
        let defaults = scratchDefaults("purchase")
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: true))
        await store.refresh()
        #expect(store.isUnlocked)
        #expect(defaults.bool(forKey: cacheKey))
    }

    /// The shipping source must be able to produce the `nil` the contract
    /// promises. A source that can only ever answer true or false makes
    /// `indeterminateAnswerKeepsTheCachedUnlock` a fiction — it would be
    /// exercising the stub while the real code path was dead. That is exactly
    /// what shipped in Kakuro build 1.
    @Test func productionSourceCanReportIndeterminate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Hashi/Store/EntitlementStore.swift"),
            encoding: .utf8)
        guard let body = source.range(of: "struct StoreKitEntitlementSource") else {
            Issue.record("could not find the production source")
            return
        }
        let production = String(source[body.lowerBound...])
        #expect(production.contains("return nil"),
                "StoreKitEntitlementSource.isOwned has no nil path, so the never-downgrade contract cannot hold on a device")
    }
}

@Suite("Hint policy")
@MainActor
struct HintPolicyTests {
    private let engine = HintEngine()

    private func game(_ puzzle: HashiPuzzle) -> HashiGame {
        HashiGame(puzzle: GeneratedHashiPuzzle(puzzle: puzzle, difficulty: .easy,
                                               techniqueProfile: [:]))
    }

    /// The whole record set is compared, not `hintedUses`. Kakuro's version
    /// asserts `hintedUses == 0`, which would pass vacuously here: Hashi's
    /// `recordHint` only bumps that counter at `>= .highlight`, and a withheld
    /// hint is always `.nudge`. `escalatingAFullHintDoesCostMastery` below is
    /// the positive control that proves this test is measuring something.
    @Test func lockedHintIsWithheldAndCostsNoMastery() {
        let game = game(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        let before = mastery.records

        let hint = engine.hint(for: game, mastery: mastery, policy: .errorsOnly)
        #expect(hint.isLocked)
        #expect(!hint.isErrorHint)
        #expect(!hint.text.contains(hint.application.technique.displayName),
                "a withheld hint must not give away the technique name")
        #expect(mastery.records == before,
                "a hint the player never saw must not touch the mastery path")
    }

    /// No withheld copy may accidentally contain any technique's display name —
    /// the short ones ("Counting", "What If", "Deep Water") are easy to slip in.
    @Test func withheldCopyNamesNoTechniqueAtAll() {
        let game = game(Fixtures.fullCorners)
        let hint = engine.hint(for: game, mastery: MasteryTracker(), policy: .errorsOnly)
        for technique in Technique.allCases {
            #expect(!hint.text.contains(technique.displayName),
                    "the withheld hint mentions \(technique.displayName)")
        }
    }

    @Test func lockedHintDoesNotEscalate() {
        let game = game(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        let hint = engine.hint(for: game, mastery: mastery, policy: .errorsOnly)
        let before = mastery.records
        let escalated = engine.escalate(hint, for: game, mastery: mastery, policy: .errorsOnly)
        #expect(escalated.level == hint.level)
        #expect(escalated.isLocked)
        #expect(mastery.records == before)
    }

    /// The positive control. Without it, the two tests above could be measuring
    /// a `recordHint` that happens to be a no-op at every level they reach.
    @Test func escalatingAFullHintDoesCostMastery() {
        let game = game(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        #expect(!hint.isLocked)
        let technique = hint.application.technique
        hint = engine.escalate(hint, for: game, mastery: mastery)   // .technique
        hint = engine.escalate(hint, for: game, mastery: mastery)   // .highlight
        #expect(hint.level == .highlight)
        #expect(mastery.record(for: technique).hintedUses == 1)
    }

    /// The error check runs before the policy guard, so free players still get
    /// told when something is wrong.
    @Test func errorHintsSurviveTheErrorsOnlyPolicy() {
        let game = game(Fixtures.chain)
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)   // past this corridor's solution value
        let hint = engine.hint(for: game, mastery: MasteryTracker(), policy: .errorsOnly)
        #expect(hint.isErrorHint)
        // Deliberately unlike Kakuro, which leaves the free error hint
        // unlocked and therefore ships a "Tell me more" that escalates to the
        // same hint and does nothing.
        #expect(hint.isLocked, "the free tier gets the nudge, not the ladder")
    }

    @Test func errorHintsDoNotClimbForFreePlayers() {
        let game = game(Fixtures.chain)
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)
        let mastery = MasteryTracker()
        let hint = engine.hint(for: game, mastery: mastery, policy: .errorsOnly)
        let escalated = engine.escalate(hint, for: game, mastery: mastery, policy: .errorsOnly)
        #expect(escalated.level == .nudge)
    }

    /// A solved-looking board says something friendly to everyone; it gives
    /// nothing away, so it is not gated.
    @Test func theNothingToDoHintIsNotGated() {
        let game = game(Fixtures.pair)
        game.cycleBridge(edge: 0)
        game.cycleBridge(edge: 0)
        game.resume()
        let hint = engine.hint(for: game, mastery: MasteryTracker(), policy: .errorsOnly)
        #expect(!hint.isLocked)
    }
}
