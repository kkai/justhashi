import Foundation
import Testing
@testable import Hashi

@Suite("Board layout")
struct BoardLayoutTests {
    private let frame = CGSize(width: 390, height: 390)

    /// A puzzle whose islands sit in the middle of a much larger grid must be
    /// laid out at the islands, not at the grid. Generation rarely reaches the
    /// edges, so roughly a fifth of every board is empty border; centring the
    /// whole grid turns that into margin and shrinks the puzzle.
    @Test func croppingToTheIslandsMakesTheBoardBigger() {
        // Islands occupy rows 4...6 and columns 4...6 of a 13x13 grid.
        let puzzle = HashiPuzzle.build(
            rows: 13, cols: 13,
            islandSpecs: [
                (GridPosition(row: 4, col: 4), 2),
                (GridPosition(row: 4, col: 6), 2),
                (GridPosition(row: 6, col: 4), 2),
                (GridPosition(row: 6, col: 6), 2),
            ],
            bridgeNetwork: [PairKey(0, 1): 1, PairKey(0, 2): 1,
                            PairKey(1, 3): 1, PairKey(2, 3): 1]
        )
        let cropped = BoardLayout(puzzle: puzzle, available: frame)
        let wholeGrid = BoardLayout(rows: 13, cols: 13, available: frame)
        #expect(cropped.pitch > wholeGrid.pitch,
                "cropping to the islands should give them more room, not less")
        #expect(cropped.rows == 3 && cropped.cols == 3)
        #expect(cropped.firstRow == 4 && cropped.firstCol == 4)
    }

    /// Every island has to land inside the frame it was laid out in, or discs
    /// clip at the edges.
    @Test(arguments: BoardSize.allCases)
    func everyIslandLandsInsideTheFrame(size: BoardSize) {
        for seed in stride(from: UInt64(400), to: 404, by: 1) {
            let puzzle = HashiGenerator.generate(
                .init(size: size, difficulty: .medium, seed: seed)).puzzle
            let layout = BoardLayout(puzzle: puzzle, available: frame)
            for island in puzzle.islands {
                let point = layout.point(for: island.position)
                #expect(point.x >= 0 && point.x <= frame.width,
                        "\(size) seed \(seed): island x \(point.x) outside the frame")
                #expect(point.y >= 0 && point.y <= frame.height,
                        "\(size) seed \(seed): island y \(point.y) outside the frame")
            }
        }
    }

    /// Hit-testing runs through the same mapping, so an island's own centre
    /// must resolve back to that island.
    @Test func hitTestingAgreesWithTheMapping() {
        let puzzle = HashiGenerator.generate(
            .init(size: .medium, difficulty: .easy, seed: 77)).puzzle
        let layout = BoardLayout(puzzle: puzzle, available: frame)
        for island in puzzle.islands {
            let point = layout.point(for: island.position)
            #expect(layout.island(at: point, in: puzzle) == island.id)
        }
    }

    /// The cap wins when a small board would otherwise be blown up to fill a
    /// large frame.
    @Test func cellCapLimitsThePitch() {
        let puzzle = Fixtures.square
        let layout = BoardLayout(puzzle: puzzle, available: CGSize(width: 900, height: 900),
                                 cellCap: 88)
        #expect(layout.pitch == 88)
    }

    /// Outer islands need clear water around them, or their rims sit on the
    /// frame edge. Half a disc is the target.
    @Test(arguments: BoardSize.allCases)
    func outerIslandsKeepClearWater(size: BoardSize) {
        let puzzle = HashiGenerator.generate(
            .init(size: size, difficulty: .medium, seed: 909)).puzzle
        let layout = BoardLayout(puzzle: puzzle, available: frame)
        let margin = layout.islandRadius * 0.4
        for island in puzzle.islands {
            let p = layout.point(for: island.position)
            let clearance = min(p.x, p.y, frame.width - p.x, frame.height - p.y)
            #expect(clearance >= layout.islandRadius + margin,
                    "island at \(island.position) has only \(clearance) of clearance")
        }
    }
}
