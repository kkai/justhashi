import Foundation
@testable import Hashi

/// Hand-built puzzles with known properties, shared across suites.
/// Diagrams: digits are island clues, rows top to bottom.
enum Fixtures {
    /// `2 . 2` — one pair, unique solution: a double bridge.
    static let pair: HashiPuzzle = .build(
        rows: 1, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),
            (GridPosition(row: 0, col: 2), 2),
        ],
        bridgeNetwork: [PairKey(0, 1): 2]
    )

    /// ```
    /// 2 . 2
    /// .   .
    /// 2 . 2
    /// ```
    /// Ring of single bridges; unique.
    static let square: HashiPuzzle = .build(
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

    /// ```
    /// 2 . 3 . 2
    /// 1 . | . 1     ← the D–E horizontal corridor crosses B–F's vertical
    /// . . 1 . .
    /// ```
    /// Islands: A(0,0)=2, B(0,2)=3, C(0,4)=2, D(1,0)=1, E(1,4)=1, F(2,2)=1.
    /// F forces the vertical B–F, which blocks the long D–E corridor, forcing
    /// D and E to connect upward. Unique; the crossing corridor stays empty.
    static let crossing: HashiPuzzle = .build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),   // 0 A
            (GridPosition(row: 0, col: 2), 3),   // 1 B
            (GridPosition(row: 0, col: 4), 2),   // 2 C
            (GridPosition(row: 1, col: 0), 1),   // 3 D
            (GridPosition(row: 1, col: 4), 1),   // 4 E
            (GridPosition(row: 2, col: 2), 1),   // 5 F
        ],
        bridgeNetwork: [
            PairKey(0, 1): 1, PairKey(1, 2): 1,   // top row
            PairKey(0, 3): 1, PairKey(2, 4): 1,   // side stubs
            PairKey(1, 5): 1,                     // vertical through (1,2)
            PairKey(3, 4): 0,                     // crossing corridor, unused
        ]
    )

    /// ```
    /// 4 . 4
    /// .   .
    /// 4 . 4
    /// ```
    /// Every corner is "full": clue 4 == 2 × two neighbors → all doubles. Unique.
    static let fullCorners: HashiPuzzle = .build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 4),
            (GridPosition(row: 0, col: 2), 4),
            (GridPosition(row: 2, col: 0), 4),
            (GridPosition(row: 2, col: 2), 4),
        ],
        bridgeNetwork: [
            PairKey(0, 1): 2, PairKey(0, 2): 2,
            PairKey(1, 3): 2, PairKey(2, 3): 2,
        ]
    )

    /// `1 . 1 . 2 . 2` risk board:
    /// completing the 1–1 pair or the 2–2 pair in isolation disconnects the rest.
    /// Unique solution: 1–1 joined via the middle, i.e. chain 1-1? No —
    /// actual layout: islands in a row, clues 1,2,2,1. Solution is the chain
    /// 1—2==2—1 (singles at the ends, double in the middle).
    static let chain: HashiPuzzle = .build(
        rows: 1, cols: 7,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 1),
            (GridPosition(row: 0, col: 2), 3),
            (GridPosition(row: 0, col: 4), 3),
            (GridPosition(row: 0, col: 6), 1),
        ],
        bridgeNetwork: [
            PairKey(0, 1): 1, PairKey(1, 2): 2, PairKey(2, 3): 1,
        ]
    )

    /// Solved board state for a fixture (its intended solution).
    static func solvedBoard(for puzzle: HashiPuzzle) -> HashiBoardState {
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        board.bridges = puzzle.solution
        return board
    }
}
