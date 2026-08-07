import Testing
@testable import Hashi

@Suite("Technique detection")
struct TechniqueDetectionTests {
    /// ```
    /// 3 . 2 . 1
    /// |       |
    /// 2 . . . 2
    /// ```
    /// D(0,0)=3 corner fires One Each Way first; the follow-up cap on E's
    /// second corridor is a Counting deduction.
    static let capacityBoard = HashiPuzzle.build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 3),   // 0 D
            (GridPosition(row: 0, col: 2), 2),   // 1 E
            (GridPosition(row: 0, col: 4), 1),   // 2 F
            (GridPosition(row: 2, col: 0), 2),   // 3 G
            (GridPosition(row: 2, col: 4), 2),   // 4 H
        ],
        bridgeNetwork: [
            PairKey(0, 1): 2, PairKey(1, 2): 0,
            PairKey(0, 3): 1, PairKey(2, 4): 1, PairKey(3, 4): 1,
        ]
    )

    /// ```
    /// 1 . 1
    /// .   .
    /// 2 . 2
    /// ```
    /// Bridging the two 1s would seal them off — the classic isolation trap.
    static let isolationBoard = HashiPuzzle.build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 1),
            (GridPosition(row: 0, col: 2), 1),
            (GridPosition(row: 2, col: 0), 2),
            (GridPosition(row: 2, col: 2), 2),
        ],
        bridgeNetwork: [
            PairKey(0, 2): 1, PairKey(1, 3): 1, PairKey(2, 3): 1,
        ]
    )

    /// 3-3-3-3 square: two symmetric solutions, deliberately ambiguous.
    static let ambiguousSquare = HashiPuzzle.build(
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

    @Test func fullIslandFiresOnFullCorners() {
        var state = LogicalSolver.State(puzzle: Fixtures.fullCorners)
        let step = LogicalSolver.nextStep(puzzle: Fixtures.fullCorners, state: &state,
                                          ceiling: .deepContradiction)
        #expect(step?.technique == .fullIsland)
        let result = LogicalSolver.solve(Fixtures.fullCorners)
        #expect(result.solved)
        #expect(Set(result.histogram.keys) == Set([Technique.fullIsland]))
    }

    @Test func onlyNeighborFiresOnChainEnd() {
        var state = LogicalSolver.State(puzzle: Fixtures.chain)
        let step = LogicalSolver.nextStep(puzzle: Fixtures.chain, state: &state,
                                          ceiling: .deepContradiction)
        #expect(step?.technique == .onlyNeighbor)
        #expect(LogicalSolver.solve(Fixtures.chain).solved)
    }

    @Test func oneEachWayFiresOnNearFullCorner() {
        let puzzle = Self.capacityBoard
        var state = LogicalSolver.State(puzzle: puzzle)
        let step = LogicalSolver.nextStep(puzzle: puzzle, state: &state,
                                          ceiling: .deepContradiction)
        #expect(step?.technique == .oneEachWay)
        #expect(step?.explanation.island == 0)
    }

    @Test func capacityCountAppearsAndBoardSolves() {
        let puzzle = Self.capacityBoard
        #expect(BacktrackingSolver.countSolutions(puzzle, limit: 4).count == 1)
        let result = LogicalSolver.solve(puzzle)
        #expect(result.solved)
        #expect(result.histogram[.capacityCount, default: 0] > 0)
    }

    @Test func isolationGuardAppearsAndBoardSolves() {
        let puzzle = Self.isolationBoard
        #expect(BacktrackingSolver.countSolutions(puzzle, limit: 4).count == 1)
        let result = LogicalSolver.solve(puzzle)
        #expect(result.solved)
        #expect(result.histogram[.isolationGuard, default: 0] > 0)
    }

    @Test func isolationGuardForbidsSealingPair() {
        let puzzle = Self.isolationBoard
        let result = LogicalSolver.solve(puzzle)
        let isolationStep = result.trace.first { $0.technique == .isolationGuard }
        let step = try! #require(isolationStep)
        // The capped corridor is the one between the two 1-islands.
        let edge = puzzle.edges[step.boundChanges[0].edge]
        #expect(Set([edge.a, edge.b]) == Set([0, 1]))
        #expect(step.boundChanges[0].newMax == 0)
    }

    @Test func segmentLinkDetectorFiresOnSingleExitGroup() {
        // 5 islands: X(0,0) Y(0,2) Z(0,4) / W(2,0) V(2,4).
        // State: X–Y and Y–Z carry proven bridges (group {X,Y,Z}); the Z–V
        // corridor is dead; X–W is the group's only exit → it must carry one.
        let puzzle = HashiPuzzle.build(
            rows: 3, cols: 5,
            islandSpecs: [
                (GridPosition(row: 0, col: 0), 3),   // 0 X
                (GridPosition(row: 0, col: 2), 2),   // 1 Y
                (GridPosition(row: 0, col: 4), 1),   // 2 Z
                (GridPosition(row: 2, col: 0), 2),   // 3 W
                (GridPosition(row: 2, col: 4), 1),   // 4 V
            ],
            bridgeNetwork: [
                PairKey(0, 1): 2, PairKey(1, 2): 0, PairKey(0, 3): 1,
                PairKey(3, 4): 1, PairKey(2, 4): 0,
            ]
        )
        var state = LogicalSolver.State(puzzle: puzzle)
        let xy = puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(0, 1) }!
        let yz = puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(1, 2) }!
        let zv = puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(2, 4) }!
        let xw = puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(0, 3) }!
        state.mins[xy.id] = 1        // open: could still become a double
        state.mins[yz.id] = 1
        state.maxs[yz.id] = 1
        state.maxs[zv.id] = 0
        let step = LogicalSolver.detectSegmentLink(puzzle, state)
        let found = try! #require(step)
        #expect(found.technique == .segmentLink)
        #expect(found.boundChanges == [BoundChange(edge: xw.id, newMin: 1, newMax: 2)])
        // Control: a fresh state has no proven group — the detector stays quiet.
        let fresh = LogicalSolver.State(puzzle: puzzle)
        #expect(LogicalSolver.detectSegmentLink(puzzle, fresh) == nil)
    }

    @Test func contradictionDetectorResolvesWhatIf() {
        // Isolation board mid-solve: assume the corridor between the two
        // 1-islands carries a bridge → both are satisfied and sealed off →
        // contradiction. The what-if detector must cap it when asked directly.
        let puzzle = Self.isolationBoard
        let state = LogicalSolver.State(puzzle: puzzle)
        let step = LogicalSolver.detectContradiction(puzzle, state, depth: 1)
        let found = try! #require(step)
        // Whatever edge it examined first, the deduction must be sound: the
        // bounds it produces must include the true solution.
        for change in found.boundChanges {
            #expect(Int(change.newMin) <= puzzle.solution[change.edge])
            #expect(Int(change.newMax) >= puzzle.solution[change.edge])
        }
    }

    @Test func ambiguousBoardStallsUnsolved() {
        let result = LogicalSolver.solve(Self.ambiguousSquare)
        #expect(!result.solved)
    }

    @Test func ceilingIsRespected() {
        // The chain needs onlyNeighbor; a fullIsland-only solver must stall.
        let result = LogicalSolver.solve(Fixtures.chain, ceiling: .fullIsland)
        #expect(!result.solved)
    }

    @Test func crossingKnowledgeIsSilent() {
        // Crossing fixture: F forces the vertical, which kills the long
        // horizontal corridor silently — the trace never needs a technique to
        // explain why D–E is unavailable.
        let result = LogicalSolver.solve(Fixtures.crossing)
        #expect(result.solved)
        #expect(result.trace.first?.technique == .onlyNeighbor)
    }

    @Test func nextStepFromPlayerBoardMatchesSolution() {
        // From an empty player board every suggested deduction must be
        // consistent with the unique solution.
        for puzzle in [Fixtures.pair, Fixtures.square, Fixtures.chain,
                       Fixtures.crossing, Self.capacityBoard, Self.isolationBoard] {
            var board = HashiBoardState(edgeCount: puzzle.edges.count)
            var guard_ = 0
            while !board.isSolved(for: puzzle), guard_ < 200 {
                guard_ += 1
                guard let step = LogicalSolver.nextStep(puzzle: puzzle, board: board) else { break }
                for change in step.boundChanges {
                    #expect(Int(change.newMin) <= puzzle.solution[change.edge],
                            "min bound exceeds solution on edge \(change.edge)")
                    #expect(Int(change.newMax) >= puzzle.solution[change.edge],
                            "max bound cuts off solution on edge \(change.edge)")
                    if change.newMin > Int8(board.bridges[change.edge]) {
                        board.bridges[change.edge] = Int(change.newMin)
                    }
                }
            }
            #expect(board.isSolved(for: puzzle), "hint walk failed to solve")
        }
    }

    @Test func solveIsDeterministic() {
        let a = LogicalSolver.solve(Self.capacityBoard)
        let b = LogicalSolver.solve(Self.capacityBoard)
        #expect(a.trace == b.trace)
    }
}
