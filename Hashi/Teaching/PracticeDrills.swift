import Foundation

/// Per-technique drill boards.
///
/// Searchable techniques use `Options.accepts` — a histogram predicate checked
/// *inside* the generator search, replacing generate-and-discard loops.
/// Techniques the shadowing audit proves unsearchable (they never appear in
/// generated solve traces — stronger arithmetic reaches the same corridors
/// first) get hand-authored boards. `handAuthored` is the source of truth and
/// `PracticeDrillTests` pins both halves.
nonisolated enum PracticeDrills {

    /// Techniques whose drills cannot be found by search. If
    /// `shadowedTechniquesStayShadowed` starts failing, detector precedence
    /// changed and this list must be revisited.
    static let handAuthored: [Technique] = [.segmentLink, .oneStepContradiction, .deepContradiction]

    static func drillPuzzle(for technique: Technique, seed: UInt64) -> GeneratedHashiPuzzle {
        if handAuthored.contains(technique) {
            return baked(technique)
        }
        let options = HashiGenerator.Options(
            size: .small,
            difficulty: requestBand(for: technique),
            seed: seed,
            accepts: { $0.techniqueProfile[technique, default: 0] >= 1 }
        )
        return HashiGenerator.generate(options)
    }

    /// The band whose ceiling admits the technique — asking for `.easy`
    /// isolation drills would be self-contradictory (easy boards are proven
    /// solvable without isolation reasoning).
    private static func requestBand(for technique: Technique) -> Difficulty {
        switch technique {
        case .fullIsland, .onlyNeighbor, .oneEachWay, .capacityCount: .easy
        case .isolationGuard: .medium
        case .segmentLink: .medium
        case .oneStepContradiction, .deepContradiction: .hard
        }
    }

    /// Hand-authored boards, shared with the lessons — proven unique by
    /// `TutorialFixtureTests`.
    private static func baked(_ technique: Technique) -> GeneratedHashiPuzzle {
        let puzzle: HashiPuzzle = switch technique {
        case .segmentLink: TutorialPuzzles.segmentBoard
        case .deepContradiction: TutorialPuzzles.deepWaterBoard
        default: TutorialPuzzles.whatIfBoard
        }
        let logical = LogicalSolver.solve(puzzle)
        return GeneratedHashiPuzzle(puzzle: puzzle, difficulty: .easy,
                                    techniqueProfile: logical.histogram)
    }
}
