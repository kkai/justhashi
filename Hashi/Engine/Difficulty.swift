import Foundation

nonisolated enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }

    /// The hardest technique a puzzle of this band may require. Enforced at
    /// generation (`LogicalSolver.solve(_:ceiling:)` must finish), which is
    /// what makes every shipped puzzle 100% teachable at its band.
    var techniqueCeiling: Technique {
        switch self {
        case .easy: .capacityCount
        case .medium: .segmentLink
        case .hard: .deepContradiction
        }
    }
}

/// Scores a solve trace into a difficulty band. Thresholds are p33/p66
/// tertiles over generated candidates per size — recalibrate (bench
/// `calibrate` command) whenever generation, density, or weights change.
nonisolated enum DifficultyRater {
    static func weight(_ technique: Technique) -> Int {
        switch technique {
        case .fullIsland: 1
        case .onlyNeighbor: 1
        case .oneEachWay: 2
        case .capacityCount: 4
        case .isolationGuard: 8
        case .segmentLink: 10
        case .oneStepContradiction: 20
        case .deepContradiction: 40
        }
    }

    static func score(profile: [Technique: Int], solved: Bool) -> Int {
        guard solved else { return 500 }
        return profile.reduce(0) { $0 + weight($1.key) * $1.value }
    }

    /// (easyMax, mediumMax) per size — scores above mediumMax are hard.
    /// Calibrated 2026-08-07 over 60 unique+solvable candidates per size
    /// (bench `calibrate`, p33/p66): small 29/35, medium 52/66, large 102/119.
    static func thresholds(for size: BoardSize) -> (easyMax: Int, mediumMax: Int) {
        switch size {
        case .small: (29, 35)
        case .medium: (52, 66)
        case .large: (102, 119)
        }
    }

    static func band(score: Int, size: BoardSize) -> Difficulty {
        let (easyMax, mediumMax) = thresholds(for: size)
        if score <= easyMax { return .easy }
        if score <= mediumMax { return .medium }
        return .hard
    }
}
