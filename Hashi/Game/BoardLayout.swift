import SwiftUI

/// The single source of truth for grid ↔ point mapping. The bridge Canvas,
/// the island views, and the gesture hit-testing all ask this — never each
/// other — so they cannot disagree.
nonisolated struct BoardLayout: Equatable {
    let rows: Int
    let cols: Int
    let pitch: CGFloat
    let origin: CGPoint
    let boardSize: CGSize

    init(rows: Int, cols: Int, available: CGSize, cellCap: CGFloat = Metrics.cellCap) {
        self.rows = rows
        self.cols = cols
        let fit = min(available.width / CGFloat(cols),
                      available.height / CGFloat(rows))
        pitch = min(cellCap, fit)
        boardSize = CGSize(width: CGFloat(cols) * pitch, height: CGFloat(rows) * pitch)
        origin = CGPoint(x: (available.width - boardSize.width) / 2,
                         y: (available.height - boardSize.height) / 2)
    }

    var islandRadius: CGFloat { pitch * 0.38 }

    func point(for position: GridPosition) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(position.col) + 0.5) * pitch,
                y: origin.y + (CGFloat(position.row) + 0.5) * pitch)
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
