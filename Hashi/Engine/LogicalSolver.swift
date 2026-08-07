import Foundation

/// The human-technique solver. `solve` grades generated puzzles (its trace is
/// the difficulty profile); `nextStep(puzzle:board:)` powers in-game hints.
///
/// State is per-edge bounds: `mins[e]`/`maxs[e]` are what has been *proven*
/// about corridor `e`. A puzzle is solved when every edge is determined and
/// the resulting board satisfies all clues and connectivity.
///
/// Crossing exclusion (a placed bridge kills the corridors it crosses) is rule
/// knowledge, not a technique: `normalize` applies it silently after every
/// step, the way the app's UI physically prevents crossing bridges.
nonisolated struct LogicalSolver: Sendable {
    struct State: Sendable {
        var mins: [Int8]
        var maxs: [Int8]

        init(puzzle: HashiPuzzle) {
            mins = [Int8](repeating: 0, count: puzzle.edges.count)
            maxs = [Int8](repeating: 2, count: puzzle.edges.count)
            LogicalSolver.normalize(state: &self, puzzle: puzzle)
        }

        init(puzzle: HashiPuzzle, board: HashiBoardState) {
            mins = board.bridges.map(Int8.init)
            maxs = [Int8](repeating: 2, count: puzzle.edges.count)
            for e in puzzle.edges.indices where mins[e] > maxs[e] { maxs[e] = mins[e] }
            LogicalSolver.normalize(state: &self, puzzle: puzzle)
        }

        func isDetermined(_ edge: Int) -> Bool { mins[edge] == maxs[edge] }

        var allDetermined: Bool {
            for e in mins.indices where mins[e] != maxs[e] { return false }
            return true
        }

        func board(edgeCount: Int) -> HashiBoardState {
            var b = HashiBoardState(edgeCount: edgeCount)
            for e in 0..<edgeCount { b.bridges[e] = Int(mins[e]) }
            return b
        }
    }

    struct SolveResult: Sendable {
        let solved: Bool
        let trace: [TechniqueApplication]

        var histogram: [Technique: Int] {
            var h: [Technique: Int] = [:]
            for step in trace { h[step.technique, default: 0] += 1 }
            return h
        }
    }

    /// Ceiling for contradiction searches so grading stays cheap and
    /// deterministic. Counts fixpoint runs, not wall clock.
    static let contradictionBudget = 4_000

    // MARK: - Public API

    static func solve(_ puzzle: HashiPuzzle) -> SolveResult {
        solve(puzzle, ceiling: .deepContradiction)
    }

    /// Solve using only techniques ≤ `ceiling` (band-teachability check).
    static func solve(_ puzzle: HashiPuzzle, ceiling: Technique) -> SolveResult {
        var state = State(puzzle: puzzle)
        var trace: [TechniqueApplication] = []
        while let step = nextStep(puzzle: puzzle, state: &state, ceiling: ceiling) {
            apply(step, to: &state, puzzle: puzzle)
            trace.append(step)
            if state.allDetermined { break }
        }
        let solved = state.allDetermined
            && state.board(edgeCount: puzzle.edges.count).isSolved(for: puzzle)
        return SolveResult(solved: solved, trace: trace)
    }

    /// A chain of deductions from the player's position ending in the first
    /// step that places a concrete bridge. Intermediate steps (max-caps like
    /// "this corridor can carry at most one") are context; `placing` is what a
    /// hint resolves to and what mastery credits (its hardest technique).
    struct HintChain: Sendable {
        let steps: [TechniqueApplication]
        let placing: TechniqueApplication

        /// The hardest technique used anywhere in the chain.
        var hardestTechnique: Technique {
            steps.map(\.technique).max() ?? placing.technique
        }
    }

    /// The next teachable deduction from the player's position, or nil.
    /// Always ends in a placeable bridge (see `HintChain`).
    static func nextStep(puzzle: HashiPuzzle, board: HashiBoardState) -> TechniqueApplication? {
        hintChain(puzzle: puzzle, board: board)?.placing
    }

    static func hintChain(puzzle: HashiPuzzle, board: HashiBoardState) -> HintChain? {
        var state = State(puzzle: puzzle, board: board)
        var steps: [TechniqueApplication] = []
        while let step = nextStep(puzzle: puzzle, state: &state, ceiling: .deepContradiction) {
            apply(step, to: &state, puzzle: puzzle)
            steps.append(step)
            let placesBridge = step.boundChanges.contains { Int($0.newMin) > board.bridges[$0.edge] }
            if placesBridge { return HintChain(steps: steps, placing: step) }
            if steps.count > 512 { break }   // safety net; detectors always narrow
        }
        return nil
    }

    static func apply(_ step: TechniqueApplication, to state: inout State, puzzle: HashiPuzzle) {
        for change in step.boundChanges {
            state.mins[change.edge] = max(state.mins[change.edge], change.newMin)
            state.maxs[change.edge] = min(state.maxs[change.edge], change.newMax)
        }
        normalize(state: &state, puzzle: puzzle)
    }

    // MARK: - Detector loop

    static func nextStep(puzzle: HashiPuzzle, state: inout State,
                         ceiling: Technique) -> TechniqueApplication? {
        for technique in Technique.allCases where technique <= ceiling {
            let step: TechniqueApplication? = switch technique {
            case .fullIsland: detectFullIsland(puzzle, state)
            case .onlyNeighbor: detectOnlyNeighbor(puzzle, state)
            case .oneEachWay: detectOneEachWay(puzzle, state)
            case .capacityCount: detectCapacityCount(puzzle, state)
            case .isolationGuard: detectIsolationGuard(puzzle, state)
            case .segmentLink: detectSegmentLink(puzzle, state)
            case .oneStepContradiction: detectContradiction(puzzle, state, depth: 1)
            case .deepContradiction: detectContradiction(puzzle, state, depth: 2)
            }
            if let step { return step }
        }
        return nil
    }

    // MARK: - Rule-level normalization (silent)

    /// A corridor a placed bridge crosses is dead. Applied silently — the UI
    /// prevents crossings physically, so this is never a "technique".
    static func normalize(state: inout State, puzzle: HashiPuzzle) {
        var changed = true
        while changed {
            changed = false
            for e in puzzle.edges.indices where state.mins[e] > 0 {
                for crosser in puzzle.crossings[e] where state.maxs[crosser] > 0 {
                    state.maxs[crosser] = 0
                    changed = true
                }
            }
        }
    }

    // MARK: - Detectors (each returns the first single application)
    // Internal, not private: detector-level fixture tests pin each one.

    static func detectFullIsland(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        for island in puzzle.islands {
            var sumMax: Int8 = 0
            var openNeighbors = 0
            for e in puzzle.edgesAt[island.id] {
                sumMax += state.maxs[e]
                if state.maxs[e] > 0 { openNeighbors += 1 }
            }
            guard sumMax == Int8(island.clue) else { continue }
            var changes: [BoundChange] = []
            var focusEdges: [Int] = []
            for e in puzzle.edgesAt[island.id] where state.mins[e] < state.maxs[e] {
                changes.append(BoundChange(edge: e, newMin: state.maxs[e], newMax: state.maxs[e]))
                focusEdges.append(e)
            }
            guard !changes.isEmpty else { continue }
            return TechniqueApplication(
                technique: .fullIsland,
                boundChanges: changes,
                focusIslands: [island.id],
                focusEdges: focusEdges,
                explanation: ExplanationData(island: island.id, clue: island.clue,
                                             neighborCount: openNeighbors)
            )
        }
        return nil
    }

    static func detectOnlyNeighbor(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        for island in puzzle.islands {
            var openEdges: [Int] = []
            var placed: Int8 = 0
            for e in puzzle.edgesAt[island.id] {
                if state.maxs[e] > 0 && !state.isDetermined(e) { openEdges.append(e) }
                placed += state.mins[e]
            }
            guard openEdges.count == 1, placed < Int8(island.clue) else { continue }
            let e = openEdges[0]
            let needed = Int8(island.clue) - (placed - state.mins[e])
            guard needed >= state.mins[e], needed <= state.maxs[e] else { continue }
            return TechniqueApplication(
                technique: .onlyNeighbor,
                boundChanges: [BoundChange(edge: e, newMin: needed, newMax: needed)],
                focusIslands: [island.id, puzzle.neighbor(of: island.id, via: e)],
                focusEdges: [e],
                explanation: ExplanationData(island: island.id, clue: island.clue, neighborCount: 1)
            )
        }
        return nil
    }

    static func detectOneEachWay(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        for island in puzzle.islands {
            var sumMax: Int8 = 0
            var openNeighbors = 0
            for e in puzzle.edgesAt[island.id] {
                sumMax += state.maxs[e]
                if state.maxs[e] > 0 { openNeighbors += 1 }
            }
            guard sumMax == Int8(island.clue) + 1 else { continue }
            var changes: [BoundChange] = []
            var focusEdges: [Int] = []
            for e in puzzle.edgesAt[island.id] where state.maxs[e] == 2 && state.mins[e] == 0 {
                changes.append(BoundChange(edge: e, newMin: 1, newMax: 2))
                focusEdges.append(e)
            }
            guard !changes.isEmpty else { continue }
            return TechniqueApplication(
                technique: .oneEachWay,
                boundChanges: changes,
                focusIslands: [island.id],
                focusEdges: focusEdges,
                explanation: ExplanationData(island: island.id, clue: island.clue,
                                             neighborCount: openNeighbors)
            )
        }
        return nil
    }

    static func detectCapacityCount(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        for island in puzzle.islands {
            var sumMin: Int8 = 0
            var sumMax: Int8 = 0
            for e in puzzle.edgesAt[island.id] {
                sumMin += state.mins[e]
                sumMax += state.maxs[e]
            }
            let clue = Int8(island.clue)
            for e in puzzle.edgesAt[island.id] where !state.isDetermined(e) {
                let newMin = clue - (sumMax - state.maxs[e])
                if newMin > state.mins[e], newMin <= state.maxs[e] {
                    return TechniqueApplication(
                        technique: .capacityCount,
                        boundChanges: [BoundChange(edge: e, newMin: newMin, newMax: state.maxs[e])],
                        focusIslands: [island.id],
                        focusEdges: [e],
                        explanation: ExplanationData(island: island.id, clue: island.clue)
                    )
                }
                let newMax = clue - (sumMin - state.mins[e])
                if newMax < state.maxs[e], newMax >= state.mins[e] {
                    return TechniqueApplication(
                        technique: .capacityCount,
                        boundChanges: [BoundChange(edge: e, newMin: state.mins[e], newMax: newMax)],
                        focusIslands: [island.id],
                        focusEdges: [e],
                        explanation: ExplanationData(island: island.id, clue: island.clue)
                    )
                }
            }
        }
        return nil
    }

    static func detectIsolationGuard(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        guard puzzle.islands.count > 2 else { return nil }
        for e in puzzle.edges.indices where !state.isDetermined(e) {
            var hi = state.maxs[e]
            var forbidden: [Int]? = nil
            while hi > state.mins[e] {
                if let group = sealedGroup(puzzle, state, ifEdge: e, wereSetTo: hi) {
                    forbidden = group
                    hi -= 1
                } else {
                    break
                }
            }
            if let group = forbidden, hi < state.maxs[e] {
                let edge = puzzle.edges[e]
                return TechniqueApplication(
                    technique: .isolationGuard,
                    boundChanges: [BoundChange(edge: e, newMin: state.mins[e], newMax: hi)],
                    focusIslands: [edge.a, edge.b],
                    focusEdges: [e],
                    explanation: ExplanationData(island: edge.a,
                                                 clue: puzzle.islands[edge.a].clue,
                                                 groupIslands: group)
                )
            }
        }
        return nil
    }

    /// The group that would become sealed (every island exactly satisfied)
    /// and isolated if `edge` carried `value` bridges — or nil.
    private static func sealedGroup(_ puzzle: HashiPuzzle, _ state: State,
                                    ifEdge edge: Int, wereSetTo value: Int8) -> [Int]? {
        var mins = state.mins
        mins[edge] = value
        let start = puzzle.edges[edge].a
        var visited = Set<Int>()
        var stack = [start]
        visited.insert(start)
        var group: [Int] = []
        while let island = stack.popLast() {
            group.append(island)
            for e in puzzle.edgesAt[island] where mins[e] > 0 {
                let next = puzzle.neighbor(of: island, via: e)
                if visited.insert(next).inserted { stack.append(next) }
            }
        }
        guard group.count < puzzle.islands.count else { return nil }
        for island in group {
            var sum: Int8 = 0
            for e in puzzle.edgesAt[island] { sum += mins[e] }
            if sum != Int8(puzzle.islands[island].clue) { return nil }
        }
        return group.sorted()
    }

    static func detectSegmentLink(_ puzzle: HashiPuzzle, _ state: State) -> TechniqueApplication? {
        guard puzzle.islands.count > 1 else { return nil }
        var visited = [Bool](repeating: false, count: puzzle.islands.count)
        for start in puzzle.islands.indices where !visited[start] {
            var group: [Int] = []
            var stack = [start]
            visited[start] = true
            while let island = stack.popLast() {
                group.append(island)
                for e in puzzle.edgesAt[island] where state.mins[e] > 0 {
                    let next = puzzle.neighbor(of: island, via: e)
                    if !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            guard group.count > 1, group.count < puzzle.islands.count else { continue }
            let groupSet = Set(group)
            var exits: [Int] = []
            for island in group {
                for e in puzzle.edgesAt[island]
                where state.maxs[e] > 0 && state.mins[e] == 0
                    && !groupSet.contains(puzzle.neighbor(of: island, via: e)) {
                    exits.append(e)
                }
            }
            if exits.count == 1, state.mins[exits[0]] == 0 {
                let e = exits[0]
                return TechniqueApplication(
                    technique: .segmentLink,
                    boundChanges: [BoundChange(edge: e, newMin: 1, newMax: state.maxs[e])],
                    focusIslands: group.sorted(),
                    focusEdges: [e],
                    explanation: ExplanationData(island: puzzle.edges[e].a,
                                                 groupIslands: group.sorted())
                )
            }
        }
        return nil
    }

    static func detectContradiction(_ puzzle: HashiPuzzle, _ state: State,
                                            depth: Int) -> TechniqueApplication? {
        var budget = contradictionBudget
        for e in puzzle.edges.indices where !state.isDetermined(e) {
            // Assume at least one more bridge than proven: contradiction ⇒ cap.
            if contradicts(puzzle, state, edge: e, lo: state.mins[e] + 1, hi: state.maxs[e],
                           depth: depth, budget: &budget) {
                let edge = puzzle.edges[e]
                return TechniqueApplication(
                    technique: depth > 1 ? .deepContradiction : .oneStepContradiction,
                    boundChanges: [BoundChange(edge: e, newMin: state.mins[e], newMax: state.mins[e])],
                    focusIslands: [edge.a, edge.b],
                    focusEdges: [e],
                    explanation: ExplanationData(island: edge.a, clue: puzzle.islands[edge.a].clue)
                )
            }
            // Assume no more bridges than proven: contradiction ⇒ raise.
            if contradicts(puzzle, state, edge: e, lo: state.mins[e], hi: state.mins[e],
                           depth: depth, budget: &budget) {
                let edge = puzzle.edges[e]
                return TechniqueApplication(
                    technique: depth > 1 ? .deepContradiction : .oneStepContradiction,
                    boundChanges: [BoundChange(edge: e, newMin: state.mins[e] + 1, newMax: state.maxs[e])],
                    focusIslands: [edge.a, edge.b],
                    focusEdges: [e],
                    explanation: ExplanationData(island: edge.a, clue: puzzle.islands[edge.a].clue)
                )
            }
            if budget <= 0 { return nil }
        }
        return nil
    }

    /// True if forcing `edge` into [lo, hi] provably fails within `depth`
    /// levels of what-if reasoning.
    private static func contradicts(_ puzzle: HashiPuzzle, _ state: State, edge: Int,
                                    lo: Int8, hi: Int8, depth: Int,
                                    budget: inout Int) -> Bool {
        guard budget > 0 else { return false }
        budget -= 1
        var mins = state.mins
        var maxs = state.maxs
        mins[edge] = lo
        maxs[edge] = hi
        guard fixpoint(puzzle, mins: &mins, maxs: &maxs) else { return true }
        guard depth > 1 else { return false }
        for f in puzzle.edges.indices where mins[f] < maxs[f] {
            guard budget > 0 else { return false }
            var aMins = mins, aMaxs = maxs
            aMins[f] = mins[f] + 1
            budget -= 1
            let canRaise = fixpoint(puzzle, mins: &aMins, maxs: &aMaxs)
            var bMins = mins, bMaxs = maxs
            bMaxs[f] = mins[f]
            budget -= 1
            let canHold = fixpoint(puzzle, mins: &bMins, maxs: &bMaxs)
            if !canRaise && !canHold { return true }
        }
        return false
    }

    /// Arithmetic + crossing + sealed-component fixpoint. Returns false on
    /// contradiction. This is rule-level propagation, shared by the what-if
    /// detectors; it deliberately mirrors `BacktrackingSolver`'s.
    static func fixpoint(_ puzzle: HashiPuzzle, mins: inout [Int8], maxs: inout [Int8]) -> Bool {
        var changed = true
        while changed {
            changed = false
            for island in puzzle.islands {
                var sumLo: Int8 = 0
                var sumHi: Int8 = 0
                for e in puzzle.edgesAt[island.id] {
                    sumLo += mins[e]
                    sumHi += maxs[e]
                }
                let clue = Int8(island.clue)
                if clue < sumLo || clue > sumHi { return false }
                for e in puzzle.edgesAt[island.id] {
                    let newLo = clue - (sumHi - maxs[e])
                    if newLo > mins[e] {
                        if newLo > maxs[e] { return false }
                        mins[e] = newLo
                        changed = true
                    }
                    let newHi = clue - (sumLo - mins[e])
                    if newHi < maxs[e] {
                        if newHi < mins[e] { return false }
                        maxs[e] = newHi
                        changed = true
                    }
                }
            }
            for e in puzzle.edges.indices where mins[e] > 0 {
                for crosser in puzzle.crossings[e] where maxs[crosser] > 0 {
                    if mins[crosser] > 0 { return false }
                    maxs[crosser] = 0
                    changed = true
                }
            }
        }
        return !hasSealedIncompleteSplit(puzzle, mins: mins, maxs: maxs)
    }

    /// A satisfied group sealed off from remaining islands is a contradiction.
    private static func hasSealedIncompleteSplit(_ puzzle: HashiPuzzle,
                                                 mins: [Int8], maxs: [Int8]) -> Bool {
        let count = puzzle.islands.count
        guard count > 1 else { return false }
        var visited = [Bool](repeating: false, count: count)
        for start in 0..<count where !visited[start] {
            var group: [Int] = []
            var stack = [start]
            visited[start] = true
            while let island = stack.popLast() {
                group.append(island)
                for e in puzzle.edgesAt[island] where mins[e] > 0 {
                    let next = puzzle.neighbor(of: island, via: e)
                    if !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            guard group.count < count else { continue }
            var sealed = true
            for island in group {
                var sumLo: Int8 = 0
                var canGrow = false
                for e in puzzle.edgesAt[island] {
                    sumLo += mins[e]
                    if mins[e] == 0 && maxs[e] > 0 { canGrow = true }
                }
                if sumLo != Int8(puzzle.islands[island].clue) || canGrow {
                    sealed = false
                    break
                }
            }
            if sealed { return true }
        }
        return false
    }
}
