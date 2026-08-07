import SwiftUI

/// The single source of truth for grid ↔ point mapping. The bridge Canvas,
/// the island views, and the gesture hit-testing all ask this — never each
/// other — so they cannot disagree.
nonisolated struct BoardLayout: Equatable {
    /// Rows and columns actually laid out: the islands' bounding box plus a
    /// margin, not the puzzle's full grid.
    let rows: Int
    let cols: Int
    /// Top-left cell of that box in puzzle coordinates, subtracted when
    /// mapping a position to a point.
    let firstRow: Int
    let firstCol: Int
    let pitch: CGFloat
    let origin: CGPoint
    let boardSize: CGSize

    /// Lays out the islands rather than the grid they happen to sit in.
    ///
    /// Generation grows a network outward from the centre and rarely reaches
    /// the edges: measured over 36 puzzles, **about 20% of every grid holds no
    /// islands at all**, at every size. Centring the whole grid turns all of
    /// that into margin, which on a large board leaves the puzzle small and
    /// marooned. Laying out the bounding box instead makes the islands roughly
    /// 12% larger and grows the touch targets with them.
    ///
    /// The margin is half a cell so the outermost discs are not flush against
    /// the frame, and so a bridge leaving the board area has somewhere to end.
    init(puzzle: HashiPuzzle, available: CGSize, cellCap: CGFloat = Metrics.cellCap) {
        let rowValues = puzzle.islands.map(\.position.row)
        let colValues = puzzle.islands.map(\.position.col)
        let minRow = rowValues.min() ?? 0
        let minCol = colValues.min() ?? 0
        let spanRows = (rowValues.max() ?? 0) - minRow + 1
        let spanCols = (colValues.max() ?? 0) - minCol + 1

        self.init(rows: spanRows, cols: spanCols, firstRow: minRow, firstCol: minCol,
                  available: available, cellCap: cellCap)
    }

    /// Extra room around the outermost islands, in cells.
    ///
    /// A cell of span already leaves half a pitch between the box edge and an
    /// outer island's centre, but a disc is 0.38 of a pitch, so that alone
    /// puts the rim within a hair of the frame. This adds 0.4 of a cell on
    /// each side, which is about half a disc of clear water.
    private static let marginCells: CGFloat = 0.8

    init(rows: Int, cols: Int, firstRow: Int = 0, firstCol: Int = 0,
         available: CGSize, cellCap: CGFloat = Metrics.cellCap) {
        self.rows = rows
        self.cols = cols
        self.firstRow = firstRow
        self.firstCol = firstCol
        let boxCols = CGFloat(cols) + Self.marginCells
        let boxRows = CGFloat(rows) + Self.marginCells
        let fit = min(available.width / boxCols, available.height / boxRows)
        pitch = min(cellCap, fit)
        boardSize = CGSize(width: boxCols * pitch, height: boxRows * pitch)
        origin = CGPoint(x: (available.width - boardSize.width) / 2,
                         y: (available.height - boardSize.height) / 2)
    }

    var islandRadius: CGFloat { pitch * 0.38 }

    func point(for position: GridPosition) -> CGPoint {
        let inset = Self.marginCells / 2
        return CGPoint(
            x: origin.x + (CGFloat(position.col - firstCol) + 0.5 + inset) * pitch,
            y: origin.y + (CGFloat(position.row - firstRow) + 0.5 + inset) * pitch)
    }

    /// Island whose disc (grown to a comfortable hit target) contains `point`.
    func island(at point: CGPoint, in puzzle: HashiPuzzle) -> Int? {
        let radius = max(islandRadius * 1.3, Metrics.islandHitTarget / 2)
        var best: (id: Int, distance: CGFloat)? = nil
        for island in puzzle.islands {
            let center = self.point(for: island.position)
            let d = hypot(point.x - center.x, point.y - center.y)
            if d <= radius, best == nil || d < best!.distance {
                best = (island.id, d)
            }
        }
        return best?.id
    }

    /// Corridor whose segment passes near `point` (and outside island discs).
    func edge(at point: CGPoint, in puzzle: HashiPuzzle) -> Int? {
        guard island(at: point, in: puzzle) == nil else { return nil }
        let tolerance = pitch * 0.3
        var best: (id: Int, distance: CGFloat)? = nil
        for edge in puzzle.edges {
            let a = self.point(for: puzzle.islands[edge.a].position)
            let b = self.point(for: puzzle.islands[edge.b].position)
            let d = distance(from: point, toSegment: a, b)
            if d <= tolerance, best == nil || d < best!.distance {
                best = (edge.id, d)
            }
        }
        return best?.id
    }

    /// Where a bridge stroke meets an island: on the rim, not the center.
    func rimPoints(for edge: Edge, in puzzle: HashiPuzzle) -> (CGPoint, CGPoint) {
        let a = point(for: puzzle.islands[edge.a].position)
        let b = point(for: puzzle.islands[edge.b].position)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let r = islandRadius
        return (CGPoint(x: a.x + cos(angle) * r, y: a.y + sin(angle) * r),
                CGPoint(x: b.x - cos(angle) * r, y: b.y - sin(angle) * r))
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return hypot(ap.x, ap.y) }
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / lengthSquared))
        let closest = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
        return hypot(p.x - closest.x, p.y - closest.y)
    }
}
