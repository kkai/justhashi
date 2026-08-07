import Foundation

/// The teaching curriculum. **Declaration order is the source of truth**: it
/// drives the solver loop, difficulty weights, hint escalation, the tutorial
/// sequence, and the practice menu. Reordering cases is a design change, not a
/// refactor — see docs/ENGINEERING.md.
nonisolated enum Technique: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    /// Clue equals twice the neighbor count (4 in a corner, 6 on an edge,
    /// 8 in the center): every corridor gets a double bridge.
    case fullIsland
    /// Only one usable corridor remains: it takes everything the clue needs.
    case onlyNeighbor
    /// Clue equals twice the neighbor count minus one (3/5/7): at least one
    /// bridge in every direction.
    case oneEachWay
    /// Capacity arithmetic: what the other corridors can still carry forces
    /// a minimum (or maximum) here.
    case capacityCount
    /// Completing a small group would seal it off from the rest — forbidden.
    case isolationGuard
    /// A nearly-finished group has exactly one way out: that corridor must
    /// carry a bridge.
    case segmentLink
    /// Assume a bridge is present (or absent); a one-step contradiction
    /// decides it.
    case oneStepContradiction
    /// The same what-if, chased two steps deep. Hard boards only.
    case deepContradiction

    var id: Int { rawValue }

    static func < (lhs: Technique, rhs: Technique) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .fullIsland: "Full Islands"
        case .onlyNeighbor: "Only Neighbor"
        case .oneEachWay: "One Each Way"
        case .capacityCount: "Counting"
        case .isolationGuard: "Don't Cut Off"
        case .segmentLink: "Stay Connected"
        case .oneStepContradiction: "What If"
        case .deepContradiction: "Deep Water"
        }
    }
}

/// One narrowed bound on one corridor.
nonisolated struct BoundChange: Sendable, Equatable {
    let edge: Int
    let newMin: Int8
    let newMax: Int8
}

/// Data the UI needs to render an explanation for a deduction.
nonisolated struct ExplanationData: Sendable, Equatable {
    var island: Int? = nil        // the island the reasoning centers on
    var clue: Int = 0
    var neighborCount: Int = 0    // usable corridors at that island
    var groupIslands: [Int] = []  // for isolation/segment reasoning
}

/// One deduction: the technique, the bounds it tightens, and what to show.
nonisolated struct TechniqueApplication: Sendable, Equatable {
    let technique: Technique
    var boundChanges: [BoundChange] = []
    var focusIslands: [Int] = []
    var focusEdges: [Int] = []
    var explanation = ExplanationData()
}
