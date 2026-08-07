import Foundation

/// Row/column coordinate on the puzzle grid. Row grows downward.
nonisolated struct GridPosition: Hashable, Codable, Sendable, Comparable {
    var row: Int
    var col: Int

    static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
        (lhs.row, lhs.col) < (rhs.row, rhs.col)
    }
}

nonisolated enum Direction: CaseIterable, Sendable {
    case up, down, left, right
}

/// A numbered island. `id` is its index into `HashiPuzzle.islands`, so the
/// solver hot paths can use flat arrays instead of dictionaries.
nonisolated struct Island: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let position: GridPosition
    let clue: Int   // 1...8
}

nonisolated enum EdgeOrientation: String, Codable, Sendable {
    case horizontal, vertical
}

/// A corridor between two aligned islands with no island in between.
/// Every geometrically possible corridor is materialized when the puzzle is
/// built; players and solvers address bridges by edge id only.
nonisolated struct Edge: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let a: Int              // island id, a < b
    let b: Int
    let orientation: EdgeOrientation
    let span: [GridPosition]   // cells strictly between the islands

    func other(_ island: Int) -> Int { island == a ? b : a }
}

/// An immutable Hashi puzzle: geometry plus the intended solution.
/// Derived indexes (`edgesAt`, `crossings`, `islandAt`) are rebuilt on init and
/// decode — they are pure functions of `islands`/`edges` and are excluded from
/// Codable so old saves stay decodable if indexing ever changes.
nonisolated struct HashiPuzzle: Codable, Sendable, Equatable {
    let rows: Int
    let cols: Int
    let islands: [Island]
    let edges: [Edge]
    let solution: [Int]   // per edge id: 0, 1, or 2

    private(set) var edgesAt: [[Int]] = []          // island id → edge ids (≤4)
    private(set) var crossings: [[Int]] = []        // edge id → ids of edges whose span intersects
    private(set) var islandAt: [GridPosition: Int] = [:]

    private enum CodingKeys: String, CodingKey {
        case rows, cols, islands, edges, solution
    }

    init(rows: Int, cols: Int, islands: [Island], edges: [Edge], solution: [Int]) {
        self.rows = rows
        self.cols = cols
        self.islands = islands
        self.edges = edges
        self.solution = solution
        buildIndexes()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode(Int.self, forKey: .rows)
        cols = try c.decode(Int.self, forKey: .cols)
        islands = try c.decode([Island].self, forKey: .islands)
        edges = try c.decode([Edge].self, forKey: .edges)
        solution = try c.decode([Int].self, forKey: .solution)
        buildIndexes()
    }

    static func == (lhs: HashiPuzzle, rhs: HashiPuzzle) -> Bool {
        lhs.rows == rhs.rows && lhs.cols == rhs.cols
            && lhs.islands == rhs.islands && lhs.edges == rhs.edges
            && lhs.solution == rhs.solution
    }

    private mutating func buildIndexes() {
        edgesAt = Array(repeating: [], count: islands.count)
        for edge in edges {
            edgesAt[edge.a].append(edge.id)
            edgesAt[edge.b].append(edge.id)
        }
        islandAt = [:]
        for island in islands { islandAt[island.position] = island.id }

        crossings = Array(repeating: [], count: edges.count)
        var cellToEdges: [GridPosition: [Int]] = [:]
        for edge in edges {
            for cell in edge.span { cellToEdges[cell, default: []].append(edge.id) }
        }
        for ids in cellToEdges.values where ids.count > 1 {
            // Only a horizontal and a vertical corridor can share a span cell.
            for i in ids {
                for j in ids where j != i {
                    if !crossings[i].contains(j) { crossings[i].append(j) }
                }
            }
        }
    }

    func neighbor(of island: Int, via edgeID: Int) -> Int {
        edges[edgeID].other(island)
    }

    /// The edge leaving `island` in `direction`, if a corridor exists there.
    func edge(from island: Int, direction: Direction) -> Int? {
        let origin = islands[island].position
        for edgeID in edgesAt[island] {
            let edge = edges[edgeID]
            let other = islands[edge.other(island)].position
            switch direction {
            case .up: if edge.orientation == .vertical, other.row < origin.row { return edgeID }
            case .down: if edge.orientation == .vertical, other.row > origin.row { return edgeID }
            case .left: if edge.orientation == .horizontal, other.col < origin.col { return edgeID }
            case .right: if edge.orientation == .horizontal, other.col > origin.col { return edgeID }
            }
        }
        return nil
    }

    /// Builds a puzzle from island placements and a solved bridge network.
    /// Materializes every geometric corridor (including unused ones) as an edge.
    /// `bridgeNetwork` maps island-pair (min id, max id) → bridge count 1...2.
    static func build(
        rows: Int, cols: Int,
        islandSpecs: [(position: GridPosition, clue: Int)],
        bridgeNetwork: [PairKey: Int]
    ) -> HashiPuzzle {
        let islands = islandSpecs.enumerated().map {
            Island(id: $0.offset, position: $0.element.position, clue: $0.element.clue)
        }
        var occupied = [GridPosition: Int]()
        for island in islands { occupied[island.position] = island.id }

        var edges: [Edge] = []
        var solution: [Int] = []

        // Horizontal corridors: scan each row left→right pairing consecutive islands.
        for row in 0..<rows {
            let inRow = islands.filter { $0.position.row == row }.sorted { $0.position.col < $1.position.col }
            for (left, right) in zip(inRow, inRow.dropFirst()) {
                let span = ((left.position.col + 1)..<right.position.col)
                    .map { GridPosition(row: row, col: $0) }
                let id = edges.count
                edges.append(Edge(id: id, a: min(left.id, right.id), b: max(left.id, right.id),
                                  orientation: .horizontal, span: span))
                solution.append(bridgeNetwork[PairKey(left.id, right.id)] ?? 0)
            }
        }
        // Vertical corridors: scan each column top→bottom.
        for col in 0..<cols {
            let inCol = islands.filter { $0.position.col == col }.sorted { $0.position.row < $1.position.row }
            for (top, bottom) in zip(inCol, inCol.dropFirst()) {
                let span = ((top.position.row + 1)..<bottom.position.row)
                    .map { GridPosition(row: $0, col: col) }
                let id = edges.count
                edges.append(Edge(id: id, a: min(top.id, bottom.id), b: max(top.id, bottom.id),
                                  orientation: .vertical, span: span))
                solution.append(bridgeNetwork[PairKey(top.id, bottom.id)] ?? 0)
            }
        }
        return HashiPuzzle(rows: rows, cols: cols, islands: islands, edges: edges, solution: solution)
    }
}

/// Unordered island pair, used when constructing puzzles from a bridge network.
nonisolated struct PairKey: Hashable, Sendable {
    let lo: Int
    let hi: Int
    init(_ x: Int, _ y: Int) {
        lo = min(x, y)
        hi = max(x, y)
    }
}

nonisolated enum BoardSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var gridRows: Int {
        switch self {
        case .small: 7
        case .medium: 10
        case .large: 13
        }
    }
    var gridCols: Int { gridRows }

    /// Target island counts for generation.
    var islandRange: ClosedRange<Int> {
        switch self {
        case .small: 9...12
        case .medium: 15...20
        case .large: 24...32
        }
    }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
