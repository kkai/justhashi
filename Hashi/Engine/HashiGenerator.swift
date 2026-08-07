import Foundation

/// A generated, verified puzzle: unique solution AND fully solvable by
/// `LogicalSolver` inside its band's technique ceiling. That pair of checks is
/// the hint guarantee — enforced here at runtime, never by convention.
nonisolated struct GeneratedHashiPuzzle: Codable, Sendable, Equatable {
    let puzzle: HashiPuzzle
    let difficulty: Difficulty
    let techniqueProfile: [Technique: Int]
}

/// Spanning-structure-first generator:
/// 1. Grow a connected bridge network island by island (random walks).
/// 2. Add cycle bridges (cycles are what create the harder deductions).
/// 3. Derive clues from bridge degrees; materialize every corridor as an edge.
/// 4. Verify: unique + teachable at the band ceiling — the single exit.
/// 5. On ambiguity, repair by perturbing a differing edge and re-verifying.
///
/// Determinism: one seeded RNG, fixed draw order, and a **node budget** (not
/// wall clock) bounding the search. Never reorder or add an RNG draw once
/// shipped — dailies are a pure function of the seeded stream.
nonisolated enum HashiGenerator {
    struct Options: Sendable {
        var size: BoardSize
        var difficulty: Difficulty
        var seed: UInt64 = .random(in: 0...UInt64.max)
        /// Drill/tutorial filter, checked against the solve histogram inside
        /// the search — replaces generate-and-discard loops.
        var accepts: @Sendable (GeneratedHashiPuzzle) -> Bool = { _ in true }

        init(size: BoardSize, difficulty: Difficulty,
             seed: UInt64 = .random(in: 0...UInt64.max),
             accepts: @escaping @Sendable (GeneratedHashiPuzzle) -> Bool = { _ in true }) {
            self.size = size
            self.difficulty = difficulty
            self.seed = seed
            self.accepts = accepts
        }
    }

    /// Cancellation/progress probes, explicit so the Engine stays independent
    /// of task context. Probes sit at cold sites only.
    struct Control: Sendable {
        var isCancelled: @Sendable () -> Bool
        var onProgress: @Sendable (Double) -> Void

        static let none = Control(isCancelled: { false }, onProgress: { _ in })
    }

    /// Backtracking-node budget per size. Deterministic; calibrated with the
    /// perf tests. Generation is cheap for Hashi — these are generous.
    static func nodeBudget(for size: BoardSize) -> Int {
        switch size {
        case .small: 200_000
        case .medium: 600_000
        case .large: 1_500_000
        }
    }

    /// Off-band candidates to reject before settling for the nearest band.
    static func maxCandidates(for size: BoardSize) -> Int {
        switch size {
        case .small: 40
        case .medium: 24
        case .large: 16
        }
    }

    /// Seeds proven (by `GenerationTests.fallbackSeedsProduceVerifiedPuzzles`)
    /// to generate quickly for every size/difficulty. Used when the budget
    /// runs out — a re-search with a known-good seed, unlike kakuro's baked
    /// grids, because Hashi repair converges fast and search is cheap.
    static let fallbackSeed: UInt64 = 0x48617368695F3141

    static func generate(_ options: Options, control: Control = .none) -> GeneratedHashiPuzzle {
        if let result = search(options, control: control) {
            return result
        }
        // Budget exhausted (or cancelled): deterministic known-good fallback.
        var fallbackOptions = options
        fallbackOptions.seed = fallbackSeed &+ UInt64(options.size.gridRows)
        fallbackOptions.accepts = { _ in true }
        if let result = search(fallbackOptions, control: .none) {
            return result
        }
        // Unreachable in practice (pinned by tests); a last-resort tiny board
        // keeps the signature non-optional.
        return verifiedMinimalBoard()
    }

    // MARK: - Search loop

    private static func search(_ options: Options, control: Control) -> GeneratedHashiPuzzle? {
        var rng = SeededRandomNumberGenerator(seed: options.seed)
        var budget = nodeBudget(for: options.size)
        var candidates = 0
        var nearest: (GeneratedHashiPuzzle, Int)? = nil   // (candidate, score distance)
        let maxCand = maxCandidates(for: options.size)

        while budget > 0 && candidates < maxCand {
            if control.isCancelled() { return nil }
            control.onProgress(1.0 - Double(budget) / Double(nodeBudget(for: options.size)))

            guard var network = growNetwork(options.size, difficulty: options.difficulty, rng: &rng) else {
                budget -= 500   // growth stall — charge a flat fee
                continue
            }
            addCycles(&network, size: options.size, difficulty: options.difficulty, rng: &rng)

            guard let verified = verifyAndRepair(network, options: options,
                                                 budget: &budget, rng: &rng) else { continue }
            candidates += 1

            let score = DifficultyRater.score(profile: verified.techniqueProfile, solved: true)
            let band = DifficultyRater.band(score: score, size: options.size)
            let graded = GeneratedHashiPuzzle(puzzle: verified.puzzle,
                                              difficulty: band,
                                              techniqueProfile: verified.techniqueProfile)
            guard options.accepts(graded) else { continue }

            if band == options.difficulty { return graded }

            let (easyMax, mediumMax) = DifficultyRater.thresholds(for: options.size)
            let target: Int = switch options.difficulty {
            case .easy: 0
            case .medium: (easyMax + mediumMax) / 2
            case .hard: mediumMax * 2
            }
            let distance = abs(score - target)
            if nearest == nil || distance < nearest!.1 {
                nearest = (graded, distance)
            }
        }
        return nearest?.0
    }

    // MARK: - Network growth

    struct Network {
        var rows: Int
        var cols: Int
        var islands: [GridPosition] = []
        var bridges: [PairKey: Int] = [:]          // island index pair → 1...2
        var islandIndex: [GridPosition: Int] = [:]
        var occupied: Set<GridPosition> = []       // island cells + bridge span cells
    }

    private static func growNetwork(_ size: BoardSize, difficulty: Difficulty,
                                    rng: inout SeededRandomNumberGenerator) -> Network? {
        let rows = size.gridRows
        let cols = size.gridCols
        var net = Network(rows: rows, cols: cols)

        let start = GridPosition(row: rows / 2 + Int.random(in: -1...1, using: &rng),
                                 col: cols / 2 + Int.random(in: -1...1, using: &rng))
        addIsland(start, to: &net)

        let target = Int.random(in: size.islandRange, using: &rng)
        let doubleChance: Double = switch difficulty {
        case .easy: 0.45
        case .medium: 0.35
        case .hard: 0.3
        }

        var stalls = 0
        while net.islands.count < target && stalls < 200 {
            let sourceIndex = Int.random(in: 0..<net.islands.count, using: &rng)
            let source = net.islands[sourceIndex]
            let direction = Direction.allCases[Int.random(in: 0..<4, using: &rng)]
            let distance = Int.random(in: 1...4, using: &rng)

            guard let placed = tryPlace(from: source, direction: direction,
                                        distance: distance, in: &net) else {
                stalls += 1
                continue
            }
            let count = Double.random(in: 0..<1, using: &rng) < doubleChance ? 2 : 1
            net.bridges[PairKey(sourceIndex, placed)] = count
            markSpan(between: source, and: net.islands[placed], in: &net)
            stalls = 0
        }
        return net.islands.count >= size.islandRange.lowerBound ? net : nil
    }

    private static func addIsland(_ position: GridPosition, to net: inout Network) {
        net.islandIndex[position] = net.islands.count
        net.islands.append(position)
        net.occupied.insert(position)
    }

    /// Places a new island `distance` cells from `source`, if the walk is clear.
    private static func tryPlace(from source: GridPosition, direction: Direction,
                                 distance: Int, in net: inout Network) -> Int? {
        var cells: [GridPosition] = []
        var cursor = source
        for _ in 0..<distance {
            cursor = step(cursor, direction)
            guard cursor.row >= 0, cursor.row < net.rows,
                  cursor.col >= 0, cursor.col < net.cols else { return nil }
            cells.append(cursor)
        }
        // Every cell of the walk, including the destination, must be free.
        for cell in cells where net.occupied.contains(cell) { return nil }
        // Keep breathing room: no island directly adjacent to the new one
        // unless it is the source (avoids unreadable clusters).
        let destination = cells.removeLast()
        addIsland(destination, to: &net)
        return net.islands.count - 1
    }

    private static func step(_ p: GridPosition, _ d: Direction) -> GridPosition {
        switch d {
        case .up: GridPosition(row: p.row - 1, col: p.col)
        case .down: GridPosition(row: p.row + 1, col: p.col)
        case .left: GridPosition(row: p.row, col: p.col - 1)
        case .right: GridPosition(row: p.row, col: p.col + 1)
        }
    }

    private static func markSpan(between a: GridPosition, and b: GridPosition,
                                 in net: inout Network) {
        if a.row == b.row {
            for col in (min(a.col, b.col) + 1)..<max(a.col, b.col) {
                net.occupied.insert(GridPosition(row: a.row, col: col))
            }
        } else {
            for row in (min(a.row, b.row) + 1)..<max(a.row, b.row) {
                net.occupied.insert(GridPosition(row: row, col: a.col))
            }
        }
    }

    /// Cycle bridges between already-placed aligned islands whose corridor is
    /// clear. Cycles break the tree structure — trees are trivially solvable.
    private static func addCycles(_ net: inout Network, size: BoardSize,
                                  difficulty: Difficulty,
                                  rng: inout SeededRandomNumberGenerator) {
        let attempts: Int = switch difficulty {
        case .easy: 2
        case .medium: 4
        case .hard: 7
        }
        var pairs: [(Int, Int)] = []
        for i in net.islands.indices {
            for j in net.islands.indices where j > i {
                let a = net.islands[i]
                let b = net.islands[j]
                guard a.row == b.row || a.col == b.col else { continue }
                guard net.bridges[PairKey(i, j)] == nil else { continue }
                guard corridorIsClear(a, b, net: net) else { continue }
                pairs.append((i, j))
            }
        }
        guard !pairs.isEmpty else { return }
        for _ in 0..<attempts {
            let pick = pairs[Int.random(in: 0..<pairs.count, using: &rng)]
            let a = net.islands[pick.0]
            let b = net.islands[pick.1]
            guard net.bridges[PairKey(pick.0, pick.1)] == nil,
                  corridorIsClear(a, b, net: net) else { continue }
            // Degree cap: an island carries at most 8 bridges.
            let count = Int.random(in: 1...2, using: &rng)
            guard degree(pick.0, net: net) + count <= 8,
                  degree(pick.1, net: net) + count <= 8 else { continue }
            net.bridges[PairKey(pick.0, pick.1)] = count
            markSpan(between: a, and: b, in: &net)
        }
    }

    private static func corridorIsClear(_ a: GridPosition, _ b: GridPosition,
                                        net: Network) -> Bool {
        if a.row == b.row {
            for col in (min(a.col, b.col) + 1)..<max(a.col, b.col) {
                if net.occupied.contains(GridPosition(row: a.row, col: col)) { return false }
            }
        } else {
            for row in (min(a.row, b.row) + 1)..<max(a.row, b.row) {
                if net.occupied.contains(GridPosition(row: row, col: a.col)) { return false }
            }
        }
        return true
    }

    private static func degree(_ island: Int, net: Network) -> Int {
        var total = 0
        for (pair, count) in net.bridges where pair.lo == island || pair.hi == island {
            total += count
        }
        return total
    }

    // MARK: - Verification & repair

    private struct Verified {
        let puzzle: HashiPuzzle
        let techniqueProfile: [Technique: Int]
    }

    private static func verifyAndRepair(_ network: Network, options: Options,
                                        budget: inout Int,
                                        rng: inout SeededRandomNumberGenerator) -> Verified? {
        var net = network
        for _ in 0..<20 {   // bounded repair rounds
            guard let puzzle = buildPuzzle(from: net) else { return nil }
            let result = BacktrackingSolver.countSolutions(puzzle, limit: 2,
                                                           nodeLimit: min(budget, 200_000))
            budget -= result.nodes + 50
            if result.aborted { return nil }
            if result.count == 0 { return nil }   // should not happen: network is a solution
            if result.count == 1 {
                let logical = LogicalSolver.solve(puzzle, ceiling: options.difficulty.techniqueCeiling)
                guard logical.solved else { return nil }
                return Verified(puzzle: puzzle, techniqueProfile: logical.histogram)
            }
            // Two solutions: perturb the network on a differing edge.
            guard repair(&net, puzzle: puzzle, solutions: result.solutions, rng: &rng) else {
                return nil
            }
        }
        return nil
    }

    /// Diff the two found solutions, pick a differing edge, and change the
    /// intended network there so the derived clues distinguish them.
    private static func repair(_ net: inout Network, puzzle: HashiPuzzle,
                               solutions: [[Int8]],
                               rng: inout SeededRandomNumberGenerator) -> Bool {
        guard solutions.count >= 2 else { return false }
        let a = solutions[0], b = solutions[1]
        var differing: [Int] = []
        for e in puzzle.edges.indices where a[e] != b[e] { differing.append(e) }
        guard !differing.isEmpty else { return false }
        let edgeID = differing[Int.random(in: 0..<differing.count, using: &rng)]
        let edge = puzzle.edges[edgeID]
        let ia = net.islandIndex[puzzle.islands[edge.a].position]!
        let ib = net.islandIndex[puzzle.islands[edge.b].position]!
        let key = PairKey(ia, ib)
        let current = net.bridges[key] ?? 0

        // Mutate the intended count on that corridor: 0→1, 1→2, 2→1.
        // Never drop to 0 (might disconnect the intended network).
        let next = current == 0 ? 1 : (current == 1 ? 2 : 1)
        guard degree(ia, net: net) - current + next <= 8,
              degree(ib, net: net) - current + next <= 8 else { return false }
        if current == 0 {
            guard corridorIsClear(net.islands[ia], net.islands[ib], net: net) else { return false }
            markSpan(between: net.islands[ia], and: net.islands[ib], in: &net)
        }
        net.bridges[key] = next
        return true
    }

    static func buildPuzzle(from net: Network) -> HashiPuzzle? {
        // Every island needs at least one bridge; degree ≤ 8.
        var degrees = [Int](repeating: 0, count: net.islands.count)
        for (pair, count) in net.bridges {
            degrees[pair.lo] += count
            degrees[pair.hi] += count
        }
        for d in degrees where d < 1 || d > 8 { return nil }

        let specs = net.islands.enumerated().map { (index, position) in
            (position: position, clue: degrees[index])
        }
        let puzzle = HashiPuzzle.build(rows: net.rows, cols: net.cols,
                                       islandSpecs: specs, bridgeNetwork: net.bridges)
        // Sanity: the network must be a valid connected solution.
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        board.bridges = puzzle.solution
        guard board.isSolved(for: puzzle) else { return nil }
        return puzzle
    }

    // MARK: - Last resort

    /// A tiny pre-verified board (the ring square) — only reachable if both
    /// the seeded search and the fallback seed fail, which tests pin as
    /// impossible.
    private static func verifiedMinimalBoard() -> GeneratedHashiPuzzle {
        let puzzle = HashiPuzzle.build(
            rows: 3, cols: 3,
            islandSpecs: [
                (GridPosition(row: 0, col: 0), 2),
                (GridPosition(row: 0, col: 2), 2),
                (GridPosition(row: 2, col: 0), 2),
                (GridPosition(row: 2, col: 2), 2),
            ],
            bridgeNetwork: [
                PairKey(0, 1): 1, PairKey(0, 2): 1,
                PairKey(1, 3): 1, PairKey(2, 3): 1,
            ]
        )
        let logical = LogicalSolver.solve(puzzle)
        return GeneratedHashiPuzzle(puzzle: puzzle, difficulty: .easy,
                                    techniqueProfile: logical.histogram)
    }
}
