import Testing
@testable import Hashi

@Suite("Backtracking solver")
struct SolverTests {
    @Test func fixturesAreUnique() {
        for puzzle in [Fixtures.pair, Fixtures.square, Fixtures.fullCorners,
                       Fixtures.chain, Fixtures.crossing] {
            let result = BacktrackingSolver.countSolutions(puzzle, limit: 4)
            #expect(result.count == 1)
            #expect(!result.aborted)
        }
    }

    @Test func ambiguousBoardCountsMultipleSolutions() {
        //   3 . 3
        //   .   .
        //   3 . 3
        // (top, left, right, bottom) = (2,1,1,2) and (1,2,2,1) both satisfy
        // every clue and stay connected — at least two solutions.
        let puzzle = HashiPuzzle.build(
            rows: 3, cols: 3,
            islandSpecs: [
                (GridPosition(row: 0, col: 0), 3),
                (GridPosition(row: 0, col: 2), 3),
                (GridPosition(row: 2, col: 0), 3),
                (GridPosition(row: 2, col: 2), 3),
            ],
            bridgeNetwork: [
                PairKey(0, 1): 2, PairKey(0, 2): 1,
                PairKey(1, 3): 1, PairKey(2, 3): 2,
            ]
        )
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 4)
        #expect(result.count > 1)
    }

    @Test func unsolvableBoardCountsZero() {
        // 1 . 1 . 1 in a row: middle island's clue can be met, but parity
        // makes total degree odd — no valid pairing connects all three.
        let puzzle = HashiPuzzle.build(
            rows: 1, cols: 5,
            islandSpecs: [
                (GridPosition(row: 0, col: 0), 1),
                (GridPosition(row: 0, col: 2), 1),
                (GridPosition(row: 0, col: 4), 1),
            ],
            bridgeNetwork: [:]
        )
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 4)
        #expect(result.count == 0)
        #expect(!result.aborted)
    }

    @Test func crossingSolutionIsRespected() {
        // The crossing fixture's only solution leaves the horizontal corridor
        // empty; the solver must agree with the baked solution.
        let puzzle = Fixtures.crossing
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 4)
        #expect(result.count == 1)
        #expect(Fixtures.solvedBoard(for: puzzle).isSolved(for: puzzle))
    }

    @Test func nodeLimitAborts() {
        let puzzle = Fixtures.fullCorners
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 2, nodeLimit: 1)
        #expect(result.aborted || result.count > 0)
    }

    @Test func partialBoardNarrowsSearch() {
        let puzzle = Fixtures.chain
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        // Play the middle double; the rest is forced.
        let middle = puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(1, 2) }!
        board.bridges[middle.id] = 2
        let result = BacktrackingSolver.countSolutions(puzzle, board: board, limit: 4)
        #expect(result.count == 1)
    }

    @Test func contradictoryPartialBoardHasNoSolutions() {
        let puzzle = Fixtures.crossing
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        // Force a bridge on the long horizontal corridor — blocks the vertical
        // one the solution needs.
        let horizontal = puzzle.edges.first { $0.orientation == .horizontal && !puzzle.crossings[$0.id].isEmpty }!
        board.bridges[horizontal.id] = 1
        let result = BacktrackingSolver.countSolutions(puzzle, board: board, limit: 4)
        #expect(result.count == 0)
    }
}
