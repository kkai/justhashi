import Foundation

/// The player's bridges, one count (0/1/2) per edge id.
nonisolated struct HashiBoardState: Codable, Sendable, Equatable {
    var bridges: [Int]

    init(edgeCount: Int) {
        bridges = Array(repeating: 0, count: edgeCount)
    }

    func bridgeCount(at island: Int, puzzle: HashiPuzzle) -> Int {
        var total = 0
        for edgeID in puzzle.edgesAt[island] { total += bridges[edgeID] }
        return total
    }

    /// True when drawing on `edgeID` is blocked by an existing bridge crossing it.
    func isBlocked(edge edgeID: Int, puzzle: HashiPuzzle) -> Bool {
        for other in puzzle.crossings[edgeID] where bridges[other] > 0 { return true }
        return false
    }

    /// A placed bridge that crosses another placed bridge (only reachable by
    /// decoding a corrupt save — the UI prevents drawing one).
    func hasCrossingViolation(puzzle: HashiPuzzle) -> Bool {
        for edge in puzzle.edges where bridges[edge.id] > 0 {
            if isBlocked(edge: edge.id, puzzle: puzzle) { return true }
        }
        return false
    }

    /// Connected components over islands joined by at least one bridge.
    /// Isolated islands each form their own component.
    func components(puzzle: HashiPuzzle) -> [[Int]] {
        var visited = Array(repeating: false, count: puzzle.islands.count)
        var result: [[Int]] = []
        for start in puzzle.islands.indices where !visited[start] {
            var component: [Int] = []
            var stack = [start]
            visited[start] = true
            while let island = stack.popLast() {
                component.append(island)
                for edgeID in puzzle.edgesAt[island] where bridges[edgeID] > 0 {
                    let next = puzzle.neighbor(of: island, via: edgeID)
                    if !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            result.append(component)
        }
        return result
    }

    func isSolved(for puzzle: HashiPuzzle) -> Bool {
        for island in puzzle.islands where bridgeCount(at: island.id, puzzle: puzzle) != island.clue {
            return false
        }
        if hasCrossingViolation(puzzle: puzzle) { return false }
        return components(puzzle: puzzle).count == 1
    }
}

/// An undoable change. `apply(to:)` returns the inverse move, so undo is a
/// plain stack of applied moves' inverses.
nonisolated indirect enum Move: Codable, Sendable, Equatable {
    case setBridge(edge: Int, old: Int, new: Int)
    case batch([Move])

    @discardableResult
    func apply(to board: inout HashiBoardState) -> Move {
        switch self {
        case let .setBridge(edge, old, new):
            board.bridges[edge] = new
            return .setBridge(edge: edge, old: new, new: old)
        case let .batch(moves):
            let inverses = moves.map { $0.apply(to: &board) }
            return .batch(inverses.reversed())
        }
    }

    var inverse: Move {
        switch self {
        case let .setBridge(edge, old, new):
            .setBridge(edge: edge, old: new, new: old)
        case let .batch(moves):
            .batch(moves.reversed().map(\.inverse))
        }
    }
}
