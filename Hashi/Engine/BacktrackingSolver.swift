import Foundation

/// Exhaustive solver used only to prove uniqueness (`countSolutions(limit: 2)`).
/// Human solving lives in `LogicalSolver`; this one is allowed to guess.
///
/// Per-edge bounds (`lo`/`hi`) are propagated with island-sum arithmetic and
/// crossing exclusion; branching picks the most-constrained undetermined edge.
/// Connectivity is enforced by a satisfied-isolated-component prune plus a
/// final check at each leaf.
nonisolated enum BacktrackingSolver {
    struct Result: Sendable {
        let count: Int
        let aborted: Bool        // node limit hit — the count is a lower bound only
        let solutions: [[Int8]]  // up to `limit` full solutions, for repair diffing
        let nodes: Int           // search nodes spent (generator budget accounting)
    }

    static func countSolutions(_ puzzle: HashiPuzzle, limit: Int = 2,
                               nodeLimit: Int = 200_000) -> Result {
        var search = Search(puzzle: puzzle, limit: limit, nodeLimit: nodeLimit)
        var lo = [Int8](repeating: 0, count: puzzle.edges.count)
        var hi = [Int8](repeating: 2, count: puzzle.edges.count)
        guard search.propagate(lo: &lo, hi: &hi) else {
            return Result(count: 0, aborted: false, solutions: [], nodes: 0)
        }
        search.explore(lo: lo, hi: hi)
        return Result(count: search.found, aborted: search.nodes >= search.nodeLimit,
                      solutions: search.solutions, nodes: search.nodes)
    }

    /// Solutions found from a partially-played board (used by tests/tools).
    static func countSolutions(_ puzzle: HashiPuzzle, board: HashiBoardState,
                               limit: Int = 2, nodeLimit: Int = 200_000) -> Result {
        var search = Search(puzzle: puzzle, limit: limit, nodeLimit: nodeLimit)
        var lo = [Int8](repeating: 0, count: puzzle.edges.count)
        var hi = [Int8](repeating: 2, count: puzzle.edges.count)
        for edge in puzzle.edges.indices where board.bridges[edge] > 0 {
            lo[edge] = Int8(board.bridges[edge])
        }
        guard search.propagate(lo: &lo, hi: &hi) else {
            return Result(count: 0, aborted: false, solutions: [], nodes: 0)
        }
        search.explore(lo: lo, hi: hi)
        return Result(count: search.found, aborted: search.nodes >= search.nodeLimit,
                      solutions: search.solutions, nodes: search.nodes)
    }

    private struct Search {
        let puzzle: HashiPuzzle
        let limit: Int
        let nodeLimit: Int
        var found = 0
        var nodes = 0
        var solutions: [[Int8]] = []

        init(puzzle: HashiPuzzle, limit: Int, nodeLimit: Int) {
            self.puzzle = puzzle
            self.limit = limit
            self.nodeLimit = nodeLimit
        }

        /// Fixpoint propagation. Returns false on contradiction.
        mutating func propagate(lo: inout [Int8], hi: inout [Int8]) -> Bool {
            var changed = true
            while changed {
                changed = false
                for island in puzzle.islands {
                    var sumLo: Int8 = 0
                    var sumHi: Int8 = 0
                    for edge in puzzle.edgesAt[island.id] {
                        sumLo += lo[edge]
                        sumHi += hi[edge]
                    }
                    let clue = Int8(island.clue)
                    if clue < sumLo || clue > sumHi { return false }
                    for edge in puzzle.edgesAt[island.id] {
                        let newLo = clue - (sumHi - hi[edge])
                        if newLo > lo[edge] {
                            if newLo > hi[edge] { return false }
                            lo[edge] = newLo
                            changed = true
                        }
                        let newHi = clue - (sumLo - lo[edge])
                        if newHi < hi[edge] {
                            if newHi < lo[edge] { return false }
                            hi[edge] = newHi
                            changed = true
                        }
                    }
                }
                for edge in puzzle.edges.indices where lo[edge] > 0 {
                    for crosser in puzzle.crossings[edge] where hi[crosser] > 0 {
                        if lo[crosser] > 0 { return false }
                        hi[crosser] = 0
                        changed = true
                    }
                }
            }
            return !hasSatisfiedIsolatedComponent(lo: lo, hi: hi)
        }

        /// A component connected by decided bridges whose islands are all
        /// exactly satisfied and whose outward corridors are all dead can
        /// never join the rest of the network.
        func hasSatisfiedIsolatedComponent(lo: [Int8], hi: [Int8]) -> Bool {
            let count = puzzle.islands.count
            guard count > 1 else { return false }
            var visited = [Bool](repeating: false, count: count)
            for start in 0..<count where !visited[start] {
                var component: [Int] = []
                var stack = [start]
                visited[start] = true
                while let island = stack.popLast() {
                    component.append(island)
                    for edge in puzzle.edgesAt[island] where lo[edge] > 0 {
                        let next = puzzle.neighbor(of: island, via: edge)
                        if !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
                if component.count == count { continue }
                var sealed = true
                for island in component {
                    var sumLo: Int8 = 0
                    for edge in puzzle.edgesAt[island] { sumLo += lo[edge] }
                    if sumLo != Int8(puzzle.islands[island].clue) { sealed = false; break }
                    for edge in puzzle.edgesAt[island] where lo[edge] == 0 && hi[edge] > 0 {
                        sealed = false; break
                    }
                    if !sealed { break }
                }
                if sealed { return true }
            }
            return false
        }

        mutating func explore(lo: [Int8], hi: [Int8]) {
            if found >= limit || nodes >= nodeLimit { return }
            nodes += 1

            // Most-constrained undetermined edge: prefer the one whose
            // endpoints have the least remaining slack.
            var branchEdge = -1
            var bestScore = Int.max
            for edge in puzzle.edges.indices where lo[edge] < hi[edge] {
                let e = puzzle.edges[edge]
                var slack = 0
                for endpoint in [e.a, e.b] {
                    var sumLo: Int8 = 0
                    var sumHi: Int8 = 0
                    for adj in puzzle.edgesAt[endpoint] {
                        sumLo += lo[adj]
                        sumHi += hi[adj]
                    }
                    slack += Int(sumHi - sumLo)
                }
                if slack < bestScore {
                    bestScore = slack
                    branchEdge = edge
                }
            }

            if branchEdge == -1 {
                // Fully determined: verify connectivity.
                var board = HashiBoardState(edgeCount: puzzle.edges.count)
                for edge in puzzle.edges.indices { board.bridges[edge] = Int(lo[edge]) }
                if board.components(puzzle: puzzle).count == 1 {
                    found += 1
                    solutions.append(lo)
                }
                return
            }

            var value = lo[branchEdge]
            while value <= hi[branchEdge] {
                var nextLo = lo
                var nextHi = hi
                nextLo[branchEdge] = value
                nextHi[branchEdge] = value
                if propagate(lo: &nextLo, hi: &nextHi) {
                    explore(lo: nextLo, hi: nextHi)
                }
                if found >= limit || nodes >= nodeLimit { return }
                value += 1
            }
        }
    }
}
