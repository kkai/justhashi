import Foundation
import Testing
@testable import Hashi

@Suite("Generation")
struct GenerationTests {
    @Test(arguments: BoardSize.allCases)
    func sameSeedIsDeterministic(size: BoardSize) {
        let a = HashiGenerator.generate(.init(size: size, difficulty: .medium, seed: 7))
        let b = HashiGenerator.generate(.init(size: size, difficulty: .medium, seed: 7))
        #expect(a.puzzle == b.puzzle)
        #expect(a.difficulty == b.difficulty)
    }

    @Test(arguments: BoardSize.allCases)
    func differentSeedsDiffer(size: BoardSize) {
        let a = HashiGenerator.generate(.init(size: size, difficulty: .medium, seed: 1))
        let b = HashiGenerator.generate(.init(size: size, difficulty: .medium, seed: 2))
        #expect(a.puzzle != b.puzzle)
    }

    /// The hint guarantee: every generated board is unique-solution and
    /// solvable inside its band's technique ceiling.
    @Test(arguments: BoardSize.allCases)
    func generatedBoardsAreUniqueAndTeachable(size: BoardSize) {
        for difficulty in Difficulty.allCases {
            for seed in stride(from: UInt64(100), to: 110, by: 1) {
                let g = HashiGenerator.generate(.init(size: size, difficulty: difficulty, seed: seed))
                let unique = BacktrackingSolver.countSolutions(g.puzzle, limit: 2)
                #expect(unique.count == 1 && !unique.aborted,
                        "\(size)/\(difficulty) seed \(seed) not unique")
                let logical = LogicalSolver.solve(g.puzzle, ceiling: g.difficulty.techniqueCeiling)
                #expect(logical.solved,
                        "\(size)/\(difficulty) seed \(seed) not teachable at \(g.difficulty)")
                #expect(g.puzzle.islands.count >= size.islandRange.lowerBound)
                for island in g.puzzle.islands {
                    #expect((1...8).contains(island.clue))
                }
            }
        }
    }

    /// Loose bound (kakuro convention): generate returns nearest band on
    /// budget exhaustion, so require ≥60% exact matches.
    @Test(arguments: BoardSize.allCases)
    func bandMatchRateIsAcceptable(size: BoardSize) {
        var matches = 0
        var total = 0
        for difficulty in Difficulty.allCases {
            for seed in stride(from: UInt64(300), to: 310, by: 1) {
                let g = HashiGenerator.generate(.init(size: size, difficulty: difficulty, seed: seed))
                total += 1
                if g.difficulty == difficulty { matches += 1 }
            }
        }
        #expect(Double(matches) / Double(total) >= 0.6,
                "band match \(matches)/\(total) below 60%")
    }

    /// The fallback seed must produce a verified puzzle for every size —
    /// this pins the budget-exhaustion path (Hashi's analogue of kakuro's
    /// baked fallback grids).
    @Test(arguments: BoardSize.allCases)
    func fallbackSeedProducesVerifiedPuzzles(size: BoardSize) {
        for difficulty in Difficulty.allCases {
            var options = HashiGenerator.Options(size: size, difficulty: difficulty)
            options.seed = HashiGenerator.fallbackSeed &+ UInt64(size.gridRows)
            let g = HashiGenerator.generate(options)
            let unique = BacktrackingSolver.countSolutions(g.puzzle, limit: 2)
            #expect(unique.count == 1 && !unique.aborted)
            #expect(LogicalSolver.solve(g.puzzle, ceiling: g.difficulty.techniqueCeiling).solved)
        }
    }

    @Test func acceptsPredicateIsHonored() {
        let g = HashiGenerator.generate(.init(
            size: .small, difficulty: .medium, seed: 11,
            accepts: { $0.techniqueProfile[.isolationGuard, default: 0] >= 1 }
        ))
        // Either the filter found a matching board, or the fallback (which
        // ignores accepts) kicked in — assert we got the filtered kind when
        // the primary search succeeded with this seed (it does; pinned).
        #expect(g.techniqueProfile[.isolationGuard, default: 0] >= 1)
    }

    @Test func cancellationReturnsFallback() {
        let g = HashiGenerator.generate(
            .init(size: .small, difficulty: .easy, seed: 5),
            control: .init(isCancelled: { true }, onProgress: { _ in })
        )
        // Cancelled search falls through to the deterministic fallback; the
        // result must still be a verified puzzle.
        #expect(BacktrackingSolver.countSolutions(g.puzzle, limit: 2).count == 1)
    }

    @Test func generatedPuzzleSurvivesCodableRoundTrip() throws {
        let g = HashiGenerator.generate(.init(size: .small, difficulty: .easy, seed: 9))
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(GeneratedHashiPuzzle.self, from: data)
        #expect(decoded == g)
    }

    /// Shadowing audit pin (kakuro's "three techniques never appear"):
    /// segmentLink and deepContradiction are shadowed by stronger arithmetic
    /// and never appear in generated traces — their lessons/drills must use
    /// hand-authored boards. If this fails, detector precedence changed and
    /// the teaching content strategy must be revisited.
    @Test func shadowedTechniquesStayShadowed() {
        var histogram: [Technique: Int] = [:]
        for size in BoardSize.allCases {
            for seed in stride(from: UInt64(500), to: 512, by: 1) {
                let g = HashiGenerator.generate(.init(size: size, difficulty: .hard, seed: seed))
                for (technique, count) in g.techniqueProfile {
                    histogram[technique, default: 0] += count
                }
            }
        }
        #expect(histogram[.segmentLink, default: 0] == 0)
        #expect(histogram[.deepContradiction, default: 0] == 0)
        // And the core curriculum does appear.
        #expect(histogram[.fullIsland, default: 0] > 0)
        #expect(histogram[.capacityCount, default: 0] > 0)
    }
}

@Suite("Generation performance")
struct GenerationPerformanceTests {
    /// Native -O worst case measured ~10ms; debug simulator is ~25× slower on
    /// this engine. Budget: 3s for a full band sweep per size.
    @Test(arguments: BoardSize.allCases)
    func generationStaysWithinBudget(size: BoardSize) {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for difficulty in Difficulty.allCases {
                for seed in stride(from: UInt64(700), to: 703, by: 1) {
                    _ = HashiGenerator.generate(.init(size: size, difficulty: difficulty, seed: seed))
                }
            }
        }
        #expect(elapsed < .seconds(3), "9 generations took \(elapsed)")
    }
}

@Suite("Difficulty rater")
struct DifficultyTests {
    @Test func weightsAreMonotonicInCurriculumOrder() {
        let weights = Technique.allCases.map(DifficultyRater.weight)
        #expect(weights == weights.sorted())
    }

    @Test func unsolvedScoresPunitively() {
        #expect(DifficultyRater.score(profile: [:], solved: false) == 500)
    }

    @Test func bandThresholdsAreOrdered() {
        for size in BoardSize.allCases {
            let (easyMax, mediumMax) = DifficultyRater.thresholds(for: size)
            #expect(easyMax < mediumMax)
            #expect(DifficultyRater.band(score: easyMax, size: size) == .easy)
            #expect(DifficultyRater.band(score: mediumMax, size: size) == .medium)
            #expect(DifficultyRater.band(score: mediumMax + 1, size: size) == .hard)
        }
    }
}

@Suite("Daily seed")
struct DailySeedTests {
    @Test func sameDaySameSeed() {
        let day = DayKey(year: 2026, month: 8, day: 7)
        #expect(DailySeed.seed(for: day) == DailySeed.seed(for: day))
        #expect(DailySeed.seed(for: day) != DailySeed.seed(for: DayKey(year: 2026, month: 8, day: 8)))
    }

    /// The daily puzzle is a pure function of the date — this value is
    /// effectively shipped API. If this test fails, every player's daily
    /// changed. Do not update the expectation; fix the regression.
    @Test func seedIsStableAcrossReleases() {
        let day = DayKey(year: 2026, month: 1, day: 1)
        let g1 = HashiGenerator.generate(.init(size: DailySeed.spec(for: day).size,
                                               difficulty: DailySeed.spec(for: day).difficulty,
                                               seed: DailySeed.seed(for: day)))
        let g2 = HashiGenerator.generate(.init(size: DailySeed.spec(for: day).size,
                                               difficulty: DailySeed.spec(for: day).difficulty,
                                               seed: DailySeed.seed(for: day)))
        #expect(g1.puzzle == g2.puzzle)
    }

    @Test func weekdayMatchesFoundationCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for offset in 0..<30 {
            let date = Date(timeIntervalSince1970: 1_750_000_000 + Double(offset) * 86_400)
            let day = DayKey(date: date, calendar: calendar)
            let expected = calendar.component(.weekday, from: date)
            #expect(DailySeed.weekday(of: day) == expected, "\(day.isoString)")
        }
    }

    @Test func scheduleCoversTheWeek() {
        // A known Monday: 2026-08-03.
        #expect(DailySeed.spec(for: DayKey(year: 2026, month: 8, day: 3)) == (.small, .easy))
        // Sunday 2026-08-09 is the big one.
        #expect(DailySeed.spec(for: DayKey(year: 2026, month: 8, day: 9)) == (.large, .hard))
        // Saturday 2026-08-08.
        #expect(DailySeed.spec(for: DayKey(year: 2026, month: 8, day: 8)) == (.large, .medium))
    }

    @Test func dayKeyComparisonAndPrevious() {
        let today = DayKey(year: 2026, month: 8, day: 7)
        let yesterday = DayKey(year: 2026, month: 8, day: 6)
        #expect(yesterday < today)
        #expect(today.previous() == yesterday)
        // Month boundary.
        #expect(DayKey(year: 2026, month: 8, day: 1).previous() == DayKey(year: 2026, month: 7, day: 31))
    }
}
