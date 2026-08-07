import Foundation
import Testing
@testable import Hashi

@MainActor
private func makeGame(_ puzzle: HashiPuzzle, difficulty: Difficulty = .easy,
                      daily: DayKey? = nil) -> HashiGame {
    let generated = GeneratedHashiPuzzle(puzzle: puzzle, difficulty: difficulty,
                                         techniqueProfile: [:])
    return HashiGame(puzzle: generated, requestedDifficulty: difficulty, dailyKey: daily)
}

@Suite("Game logic")
@MainActor
struct GameLogicTests {
    @Test func cycleWalksZeroOneTwoZero() {
        let game = makeGame(Fixtures.pair)
        let edge = 0
        #expect(game.cycleBridge(edge: edge) == .drewSingle)
        #expect(game.board.bridges[edge] == 1)
        #expect(game.cycleBridge(edge: edge) == .drewDouble)
        #expect(game.board.bridges[edge] == 2)
        // The pair puzzle wins at 2 — bridge state is kept; further input is
        // rejected once won.
        #expect(game.phase == .won)
        #expect(game.cycleBridge(edge: edge) == .blocked)
    }

    @Test func blockedCorridorIsRejected() {
        let game = makeGame(Fixtures.crossing)
        let vertical = Fixtures.crossing.edges.first {
            $0.orientation == .vertical && !Fixtures.crossing.crossings[$0.id].isEmpty
        }!
        let horizontal = Fixtures.crossing.edges.first {
            $0.orientation == .horizontal && !Fixtures.crossing.crossings[$0.id].isEmpty
        }!
        #expect(game.cycleBridge(edge: vertical.id) == .drewSingle)
        #expect(game.cycleBridge(edge: horizontal.id) == .blocked)
        #expect(game.board.bridges[horizontal.id] == 0)
        #expect(game.dragTarget(from: horizontal.a, direction: .right) == nil
                || game.dragTarget(from: horizontal.a, direction: .left) == nil)
    }

    @Test func overfillIsAllowedAndVisible() {
        let game = makeGame(Fixtures.chain)
        // Island 0 has clue 1; drawing a double overfills it.
        let edge = Fixtures.chain.edgesAt[0][0]
        game.cycleBridge(edge: edge)
        game.cycleBridge(edge: edge)
        #expect(game.board.bridges[edge] == 2)
        #expect(game.isOverfilled(0))
        #expect(game.remaining(at: 0) == -1)
    }

    @Test func undoRestoresBoard() {
        let game = makeGame(Fixtures.square)
        game.cycleBridge(edge: 0)
        game.cycleBridge(edge: 1)
        #expect(game.board.bridges[0] == 1 && game.board.bridges[1] == 1)
        game.undo()
        #expect(game.board.bridges[1] == 0)
        game.undo()
        #expect(game.board.bridges[0] == 0)
        #expect(!game.canUndo)
    }

    @Test func winRequiresConnectivity() {
        let game = makeGame(Fixtures.square)
        for edge in Fixtures.square.edges.indices {
            game.cycleBridge(edge: edge)
        }
        #expect(game.phase == .won)
    }

    @Test func satisfiedIsolatedComponentIsSurfaced() {
        // 1–1 pair plus more islands: joining the pair satisfies both but
        // isolates them.
        let puzzle = TechniqueDetectionTests.isolationBoard
        let game = makeGame(puzzle)
        let pairEdge = puzzle.edges.first { Set([$0.a, $0.b]) == Set([0, 1]) }!
        game.cycleBridge(edge: pairEdge.id)
        #expect(game.satisfiedIsolatedComponent()?.sorted() == [0, 1])
        game.undo()
        #expect(game.satisfiedIsolatedComponent() == nil)
    }

    @Test func autoCompleteDrawsOnlyForcedBridges() {
        let game = makeGame(Fixtures.fullCorners)
        game.autoCompleteForcedIslands()
        // Every island is "full" (clue == 2×neighbors) — the whole board is
        // forced by technique 1 and completes.
        #expect(game.phase == .won)
        // One undoable batch: a single undo unwinds it all.
        game.resume()
        #expect(game.undoStack.count == 1)
    }

    @Test func autoCompleteLeavesUnforcedBoardsAlone() {
        let game = makeGame(TechniqueDetectionTests.ambiguousSquare)
        game.autoCompleteForcedIslands()
        #expect(game.board.bridges.allSatisfy { $0 == 0 })
    }

    @Test func applyHintPlacesForcedBridges() {
        let game = makeGame(Fixtures.pair)
        let step = LogicalSolver.nextStep(puzzle: game.puzzle, board: game.board)
        let found = try! #require(step)
        game.apply(found)
        #expect(game.board.bridges[0] == 2)
        #expect(game.phase == .won)
    }

    @Test func masteryCreditPaysOncePerEdge() {
        let game = makeGame(Fixtures.square)
        #expect(game.claimMasteryCredit(edge: 0))
        #expect(!game.claimMasteryCredit(edge: 0))
        #expect(game.claimMasteryCredit(edge: 1))
    }

    @Test func pauseStopsTheClock() {
        let game = makeGame(Fixtures.square)
        let start = Date(timeIntervalSince1970: 1000)
        game.tick(now: start)
        game.tick(now: start.addingTimeInterval(5))
        #expect(abs(game.elapsed - 5) < 0.001)
        game.pause()
        game.tick(now: start.addingTimeInterval(500))   // background overnight
        #expect(abs(game.elapsed - 5) < 0.001)
        game.resume()
        game.tick(now: start.addingTimeInterval(500))
        game.tick(now: start.addingTimeInterval(503))
        #expect(abs(game.elapsed - 8) < 0.001)
    }

    @Test func snapshotRoundTrip() throws {
        let game = makeGame(Fixtures.chain, difficulty: .medium,
                            daily: DayKey(year: 2026, month: 8, day: 7))
        game.cycleBridge(edge: 0)
        let data = try JSONEncoder().encode(game.snapshot)
        let snapshot = try JSONDecoder().decode(HashiGame.Snapshot.self, from: data)
        let restored = HashiGame(snapshot: snapshot)
        #expect(restored.board == game.board)
        #expect(restored.requestedDifficulty == .medium)
        #expect(restored.dailyKey == DayKey(year: 2026, month: 8, day: 7))
        #expect(restored.canUndo)
    }

    @Test func rippleDistancesFollowBridges() {
        let game = makeGame(Fixtures.chain)
        for edge in Fixtures.chain.edges.indices {
            game.cycleBridge(edge: edge)
        }
        game.cycleBridge(edge: 1)   // second bridge on the middle corridor
        let distances = game.rippleDistances(from: 0)
        #expect(distances[0] == 0)
        #expect(distances[1] == 1)
        #expect(distances[2] == 2)
        #expect(distances[3] == 3)
    }
}

@Suite("Persistence")
@MainActor
struct PersistenceTests {
    private func freshDefaults() -> UserDefaults {
        let name = "hashi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func savedGameIsVisibleImmediatelyAndAfterRelaunch() {
        let name = "hashi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ProgressStore(userDefaults: defaults)
        #expect(store.savedGame == nil)
        let game = makeGame(Fixtures.square)
        game.cycleBridge(edge: 0)
        store.saveGame(game.snapshot)
        // Visible immediately (observable state, not a defaults read)…
        #expect(store.savedGame != nil)
        // …and after "relaunch" (a second store over the same defaults).
        let secondLaunch = ProgressStore(userDefaults: defaults)
        #expect(secondLaunch.savedGame?.board == game.board)
        store.clearSavedGame()
        #expect(store.savedGame == nil)
        #expect(ProgressStore(userDefaults: defaults).savedGame == nil)
    }

    @Test func solvesFileUnderRequestedDifficulty() {
        let store = ProgressStore(userDefaults: freshDefaults())
        // The player asked for hard; the generator delivered medium. Records
        // key on the request.
        let generated = GeneratedHashiPuzzle(puzzle: Fixtures.square,
                                             difficulty: .medium, techniqueProfile: [:])
        let game = HashiGame(puzzle: generated, requestedDifficulty: .hard)
        #expect(game.difficultyForRecords == .hard)
        store.recordSolve(size: .small, difficulty: game.difficultyForRecords, time: 100)
        #expect(store.stats.solvedByDifficulty[.hard] == 1)
        #expect(store.stats.solvedByDifficulty[.medium] == nil)
    }

    @Test func bestTimesOnlyImprove() {
        let store = ProgressStore(userDefaults: freshDefaults())
        #expect(store.recordSolve(size: .small, difficulty: .easy, time: 120))
        #expect(!store.recordSolve(size: .small, difficulty: .easy, time: 200))
        #expect(store.bestTime(size: .small, difficulty: .easy) == 120)
        #expect(store.recordSolve(size: .small, difficulty: .easy, time: 90))
        #expect(store.bestTime(size: .small, difficulty: .easy) == 90)
    }

    @Test func settingsPersist() {
        let name = "hashi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ProgressStore(userDefaults: defaults)
        store.settings.showRemainingCount = true
        store.settings.hapticsEnabled = false
        let relaunched = ProgressStore(userDefaults: defaults)
        #expect(relaunched.settings.showRemainingCount)
        #expect(!relaunched.settings.hapticsEnabled)
    }
}

@Suite("Daily streaks")
@MainActor
struct DailyStreakTests {
    private func freshStore() -> ProgressStore {
        let name = "hashi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ProgressStore(userDefaults: defaults)
    }

    @Test func consecutiveDaysGrowTheStreak() {
        let store = freshStore()
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 5), time: 100)
        #expect(store.daily.currentStreak == 1)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 6), time: 100)
        #expect(store.daily.currentStreak == 2)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 7), time: 100)
        #expect(store.daily.currentStreak == 3)
        #expect(store.daily.bestStreak == 3)
    }

    @Test func gapResetsToOne() {
        let store = freshStore()
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 1), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 2), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 5), time: 100)
        #expect(store.daily.currentStreak == 1)
        #expect(store.daily.bestStreak == 2)
    }

    @Test func repeatCompletionIsIdempotent() {
        let store = freshStore()
        let day = DayKey(year: 2026, month: 8, day: 7)
        store.recordDailyCompleted(day: day, time: 100)
        store.recordDailyCompleted(day: day, time: 50)
        #expect(store.daily.currentStreak == 1)
        #expect(store.dailyTime(day) == 100)   // first completion stands
    }

    @Test func monthBoundaryCounts() {
        let store = freshStore()
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 7, day: 31), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 1), time: 100)
        #expect(store.daily.currentStreak == 2)
    }

    @Test func displayStreakGoesStaleAfterMissedDay() {
        let store = freshStore()
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 1), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 2), time: 100)
        // Two days later, unplayed: the shown streak is 0 even though the
        // stored counter still says 2.
        #expect(store.displayStreak(today: DayKey(year: 2026, month: 8, day: 4)) == 0)
        // The day right after the last completion still shows the chain.
        #expect(store.displayStreak(today: DayKey(year: 2026, month: 8, day: 3)) == 2)
        #expect(store.streakIsAtRisk(today: DayKey(year: 2026, month: 8, day: 3)))
    }

    @Test func replayingAnOlderDayNeverRewindsTheChain() {
        let store = freshStore()
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 6), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 7), time: 100)
        store.recordDailyCompleted(day: DayKey(year: 2026, month: 8, day: 1), time: 100)
        #expect(store.daily.lastCompleted == DayKey(year: 2026, month: 8, day: 7))
    }
}
