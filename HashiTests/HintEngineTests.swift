import Foundation
import Testing
@testable import Hashi

@MainActor
private func gameFor(_ puzzle: HashiPuzzle) -> HashiGame {
    HashiGame(puzzle: GeneratedHashiPuzzle(puzzle: puzzle, difficulty: .easy,
                                           techniqueProfile: [:]))
}

@Suite("Hint engine")
@MainActor
struct HintEngineTests {
    private let engine = HintEngine()

    @Test func errorsComeBeforeTeaching() {
        let game = gameFor(Fixtures.chain)
        // Overdraw the first corridor beyond its solution value.
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)   // solution has 1 here → error
        let mastery = MasteryTracker()
        let hint = engine.hint(for: game, mastery: mastery)
        #expect(hint.isErrorHint)
    }

    @Test func showErrorsOffTeachesInstead() {
        let game = gameFor(Fixtures.chain)
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)
        let hint = engine.hint(for: game, mastery: MasteryTracker(), showErrors: false)
        #expect(!hint.isErrorHint)
    }

    @Test func escalationClimbsTheLadder() {
        let game = gameFor(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        #expect(hint.level == .nudge)
        #expect(hint.highlightIslands.isEmpty)
        #expect(hint.application.technique == .fullIsland)

        hint = engine.escalate(hint, for: game, mastery: mastery)
        #expect(hint.level == .technique)
        #expect(hint.text == TechniqueContent.rule(for: .fullIsland))

        hint = engine.escalate(hint, for: game, mastery: mastery)
        #expect(hint.level == .highlight)
        #expect(!hint.highlightIslands.isEmpty || !hint.highlightEdges.isEmpty)

        hint = engine.escalate(hint, for: game, mastery: mastery)
        #expect(hint.level == .resolution)
        // Resolution stays put on further escalation.
        let same = engine.escalate(hint, for: game, mastery: mastery)
        #expect(same.level == .resolution)
    }

    @Test func hintsRecordAgainstMastery() {
        let game = gameFor(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        hint = engine.escalate(hint, for: game, mastery: mastery)
        hint = engine.escalate(hint, for: game, mastery: mastery)   // highlight level
        #expect(mastery.record(for: .fullIsland).hintedUses >= 1)
    }

    @Test func applyingTheResolutionSolvesTheStep() {
        let game = gameFor(Fixtures.pair)
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        for _ in 0..<3 { hint = engine.escalate(hint, for: game, mastery: mastery) }
        #expect(hint.level == .resolution)
        game.apply(hint.application)
        #expect(game.phase == .won)
    }

    @Test func solvedBoardHintIsGraceful() {
        let game = gameFor(Fixtures.pair)
        game.cycleBridge(edge: 0)
        game.cycleBridge(edge: 0)   // wins
        game.resume()               // force back to playing to query
        let hint = engine.hint(for: game, mastery: MasteryTracker())
        #expect(!hint.isErrorHint)
    }
}

@Suite("Mastery")
@MainActor
struct MasteryTests {
    @Test func unaidedForcedBridgeEarnsCredit() {
        let game = gameFor(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        game.cycleBridge(edge: 0)
        game.cycleBridge(edge: 0)   // the forced double on a full island
        mastery.recordBridge(edge: 0, game: game, unaided: true)
        #expect(mastery.record(for: .fullIsland).unaidedUses == 1)
    }

    @Test func aidedBridgeEarnsNothing() {
        let game = gameFor(Fixtures.fullCorners)
        let mastery = MasteryTracker()
        game.cycleBridge(edge: 0)
        game.cycleBridge(edge: 0)
        mastery.recordBridge(edge: 0, game: game, unaided: false)
        #expect(mastery.record(for: .fullIsland).unaidedUses == 0)
    }

    @Test func wrongBridgeEarnsNothing() {
        let game = gameFor(Fixtures.chain)
        let mastery = MasteryTracker()
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)   // overfill beyond solution
        mastery.recordBridge(edge: edge, game: game, unaided: true)
        for technique in Technique.allCases {
            #expect(mastery.record(for: technique).unaidedUses == 0)
        }
    }

    @Test func learnedThresholdPromotesAndUnlocksNext() {
        let mastery = MasteryTracker()
        #expect(mastery.state(of: .oneEachWay) == .locked)
        for _ in 0..<MasteryTracker.learnedThreshold {
            mastery.recordDrillCompleted(.onlyNeighbor, unaided: true)
        }
        #expect(mastery.state(of: .onlyNeighbor) == .learned)
        #expect(mastery.state(of: .oneEachWay) == .introduced)
    }

    @Test func lessonCompletionAdvancesAndUnlocks() {
        let mastery = MasteryTracker()
        mastery.recordLessonCompleted(.oneEachWay)
        #expect(mastery.state(of: .oneEachWay) == .practicing)
        #expect(mastery.state(of: .capacityCount) == .introduced)
    }

    /// The curriculum is a ladder: crediting a later technique (play credits
    /// the hardest step in a deduction chain, which can skip ahead) must never
    /// leave an earlier one locked.
    @Test func creditingALaterTechniqueLeavesNoLockedGap() {
        let mastery = MasteryTracker()
        #expect(mastery.state(of: .oneEachWay) == .locked)
        mastery.recordDrillCompleted(.capacityCount, unaided: true)
        for earlier in Technique.allCases where earlier < .capacityCount {
            #expect(mastery.state(of: earlier) != .locked,
                    "\(earlier) is still locked behind capacityCount")
        }
        // Techniques after it stay locked until earned.
        #expect(mastery.state(of: .segmentLink) == .locked)
    }

    @Test func masteryPersistsThroughStore() {
        let name = "hashi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ProgressStore(userDefaults: defaults)
        let mastery = MasteryTracker(store: store)
        mastery.recordLessonCompleted(.fullIsland)
        let reloaded = MasteryTracker(store: ProgressStore(userDefaults: defaults))
        #expect(reloaded.record(for: .fullIsland).lessonCompleted)
    }
}
