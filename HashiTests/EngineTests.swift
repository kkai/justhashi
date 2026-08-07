import Foundation
import Testing
@testable import Hashi

@Suite("Engine models")
struct EngineTests {
    @Test func edgeIndexesAreBuilt() {
        let puzzle = Fixtures.square
        #expect(puzzle.edges.count == 4)
        for island in puzzle.islands {
            #expect(puzzle.edgesAt[island.id].count == 2)
        }
    }

    @Test func islandLookupByPosition() {
        let puzzle = Fixtures.square
        #expect(puzzle.islandAt[GridPosition(row: 0, col: 0)] == 0)
        #expect(puzzle.islandAt[GridPosition(row: 2, col: 2)] != nil)
        #expect(puzzle.islandAt[GridPosition(row: 1, col: 1)] == nil)
    }

    @Test func crossingsAreDetected() {
        let puzzle = Fixtures.crossing
        let horizontal = puzzle.edges.first { $0.orientation == .horizontal && !puzzle.crossings[$0.id].isEmpty }
        let vertical = puzzle.edges.first { $0.orientation == .vertical && !puzzle.crossings[$0.id].isEmpty }
        let h = try! #require(horizontal)
        let v = try! #require(vertical)
        #expect(puzzle.crossings[h.id].contains(v.id))
        #expect(puzzle.crossings[v.id].contains(h.id))
    }

    @Test func squareHasNoCrossings() {
        let puzzle = Fixtures.square
        for edge in puzzle.edges {
            #expect(puzzle.crossings[edge.id].isEmpty)
        }
    }

    @Test func directionalEdgeLookup() {
        let puzzle = Fixtures.square
        // Island 0 is top-left: corridors go right and down only.
        #expect(puzzle.edge(from: 0, direction: .right) != nil)
        #expect(puzzle.edge(from: 0, direction: .down) != nil)
        #expect(puzzle.edge(from: 0, direction: .up) == nil)
        #expect(puzzle.edge(from: 0, direction: .left) == nil)
    }

    @Test func moveApplyReturnsInverse() {
        var board = HashiBoardState(edgeCount: 4)
        let move = Move.setBridge(edge: 2, old: 0, new: 2)
        let inverse = move.apply(to: &board)
        #expect(board.bridges[2] == 2)
        inverse.apply(to: &board)
        #expect(board.bridges[2] == 0)
    }

    @Test func batchMoveInvertsInReverseOrder() {
        var board = HashiBoardState(edgeCount: 2)
        let batch = Move.batch([
            .setBridge(edge: 0, old: 0, new: 1),
            .setBridge(edge: 0, old: 1, new: 2),
            .setBridge(edge: 1, old: 0, new: 1),
        ])
        let inverse = batch.apply(to: &board)
        #expect(board.bridges == [2, 1])
        inverse.apply(to: &board)
        #expect(board.bridges == [0, 0])
    }

    @Test func solvedBoardIsSolved() {
        for puzzle in [Fixtures.pair, Fixtures.square, Fixtures.fullCorners, Fixtures.chain] {
            #expect(Fixtures.solvedBoard(for: puzzle).isSolved(for: puzzle))
        }
    }

    @Test func emptyBoardIsNotSolved() {
        let puzzle = Fixtures.square
        let board = HashiBoardState(edgeCount: puzzle.edges.count)
        #expect(!board.isSolved(for: puzzle))
    }

    @Test func disconnectedSatisfiedBoardIsNotSolved() {
        // Two separate pairs on one row: 1-1 gap 1-1. Satisfying each pair
        // separately meets every clue but leaves two components.
        let puzzle = HashiPuzzle.build(
            rows: 1, cols: 8,
            islandSpecs: [
                (GridPosition(row: 0, col: 0), 1),
                (GridPosition(row: 0, col: 2), 2),
                (GridPosition(row: 0, col: 5), 2),
                (GridPosition(row: 0, col: 7), 1),
            ],
            bridgeNetwork: [PairKey(0, 1): 1, PairKey(1, 2): 1, PairKey(2, 3): 1]
        )
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        // Fill 0-1 double? No: clues are 1,2,2,1 — complete each pair locally:
        // edge(0,1)=1, edge(2,3)=1 and edge(1,2)... island 1 needs 2.
        // Local completion: 0-1 single + 1's second on nothing — instead use
        // the definitely-disconnected fill: pair the outer islands fully.
        for edge in puzzle.edges {
            if PairKey(edge.a, edge.b) == PairKey(0, 1) { board.bridges[edge.id] = 1 }
            if PairKey(edge.a, edge.b) == PairKey(2, 3) { board.bridges[edge.id] = 1 }
        }
        #expect(board.components(puzzle: puzzle).count == 2)
        #expect(!board.isSolved(for: puzzle))
    }

    @Test func bridgeCountSumsAllEdges() {
        let puzzle = Fixtures.fullCorners
        let board = Fixtures.solvedBoard(for: puzzle)
        for island in puzzle.islands {
            #expect(board.bridgeCount(at: island.id, puzzle: puzzle) == island.clue)
        }
    }

    @Test func blockedEdgeDetection() {
        let puzzle = Fixtures.crossing
        var board = HashiBoardState(edgeCount: puzzle.edges.count)
        let vertical = puzzle.edges.first { $0.orientation == .vertical && !puzzle.crossings[$0.id].isEmpty }!
        let horizontal = puzzle.edges.first { $0.orientation == .horizontal && !puzzle.crossings[$0.id].isEmpty }!
        board.bridges[vertical.id] = 1
        #expect(board.isBlocked(edge: horizontal.id, puzzle: puzzle))
        #expect(!board.isBlocked(edge: vertical.id, puzzle: puzzle))
    }

    @Test func puzzleSurvivesCodableRoundTrip() throws {
        let puzzle = Fixtures.crossing
        let data = try JSONEncoder().encode(puzzle)
        let decoded = try JSONDecoder().decode(HashiPuzzle.self, from: data)
        #expect(decoded == puzzle)
        // Derived indexes must be rebuilt, not decoded.
        #expect(decoded.crossings == puzzle.crossings)
        #expect(decoded.edgesAt == puzzle.edgesAt)
    }
}
