import SwiftUI

/// The board: bridges as ink strokes, islands as paper discs.
///
/// Layers, bottom to top:
/// 1. bridge Canvas: corridor glows, placed bridges, the drag ghost
/// 2. island discs (real views, so they are accessibility elements and
///    animation anchors)
/// 3. one gesture overlay owning the drag and tap logic
///
/// The water underneath belongs to `SeaBackground`, which covers the whole
/// screen. This view used to paint its own, which meant the texture stopped
/// abruptly at the board's square frame.
///
/// Input goes through the `onTapIsland`/`onCycleEdge` callbacks rather than
/// straight into the game, so a tutorial can intercept moves (a lesson that
/// can be walked out from under is Kakuro's hardest-won UI lesson).
struct BoardView: View {
    let game: HashiGame
    var rippleDistances: [Int: Int]? = nil
    var highlightedIslands: Set<Int> = []
    var highlightedEdges: Set<Int> = []
    var warningIslands: Set<Int> = []
    var onTapIsland: (Int) -> Void
    var onCycleEdge: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dragOrigin: Int?
    @State private var ghostEdge: Int?
    @State private var rejectedIsland: Int?
    @State private var entranceDone = false

    var body: some View {
        GeometryReader { proxy in
            let layout = BoardLayout(
                puzzle: game.puzzle,
                available: proxy.size,
                cellCap: Metrics.cellCap(regularWidth: horizontalSizeClass == .regular))
            ZStack {
                bridgeCanvas(layout)
                islands(layout)
            }
            .contentShape(Rectangle())
            .gesture(boardGesture(layout))
        }
        .onAppear {
            if reduceMotion {
                entranceDone = true
            } else {
                withAnimation(Motion.boardEntrance) { entranceDone = true }
            }
        }
    }

    // MARK: - Bridges

    private func bridgeCanvas(_ layout: BoardLayout) -> some View {
        Canvas { context, _ in
            // Corridor glow for the selected island's open corridors.
            if let selected = game.selected {
                for edgeID in game.openCorridors(from: selected) {
                    let (a, b) = layout.rimPoints(for: game.puzzle.edges[edgeID], in: game.puzzle)
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(Theme.bridgeWash),
                                   style: StrokeStyle(lineWidth: layout.pitch * 0.42,
                                                      lineCap: .round))
                }
            }
            // Hint highlight on specific corridors.
            for edgeID in highlightedEdges {
                let (a, b) = layout.rimPoints(for: game.puzzle.edges[edgeID], in: game.puzzle)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(Theme.bridgeWash),
                               style: StrokeStyle(lineWidth: layout.pitch * 0.42, lineCap: .round))
            }
            // Placed bridges.
            for edge in game.puzzle.edges {
                let count = game.board.bridges[edge.id]
                guard count > 0 else { continue }
                let fading = ghostEdge == edge.id && count == 2   // next cycle clears
                drawBridge(edge, count: count, layout: layout, context: context,
                           color: Theme.bridge, opacity: fading ? 0.35 : 1)
            }
            // Ghost preview of the drag result.
            if let ghostEdge, game.board.bridges[ghostEdge] < 2 {
                let edge = game.puzzle.edges[ghostEdge]
                let next = game.board.bridges[ghostEdge] + 1
                drawBridge(edge, count: next, layout: layout, context: context,
                           color: Theme.bridgeGhost, opacity: 1)
            }
        }
        .allowsHitTesting(false)
        .animation(Motion.selection, value: game.selected)
    }

    private func drawBridge(_ edge: Edge, count: Int, layout: BoardLayout,
                            context: GraphicsContext, color: Color, opacity: Double) {
        let (a, b) = layout.rimPoints(for: edge, in: game.puzzle)
        let width = max(2.5, layout.pitch * 0.055)
        let separation = max(3.0, layout.pitch * 0.085)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        let offsets: [CGFloat] = count == 2 ? [-separation / 2, separation / 2] : [0]
        for offset in offsets {
            var path = Path()
            path.move(to: CGPoint(x: a.x + normal.x * offset, y: a.y + normal.y * offset))
            path.addLine(to: CGPoint(x: b.x + normal.x * offset, y: b.y + normal.y * offset))
            context.stroke(path, with: .color(color.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    // MARK: - Islands

    private func islands(_ layout: BoardLayout) -> some View {
        ForEach(game.puzzle.islands) { island in
            IslandView(
                island: island,
                game: game,
                radius: layout.islandRadius,
                isSelected: game.selected == island.id,
                isHighlighted: highlightedIslands.contains(island.id),
                isWarning: warningIslands.contains(island.id),
                isRejected: rejectedIsland == island.id,
                rippleHop: rippleDistances?[island.id],
                entranceDelay: entranceDelay(island, layout: layout),
                entranceDone: entranceDone
            )
            .position(layout.point(for: island.position))
        }
    }

    private func entranceDelay(_ island: Island, layout: BoardLayout) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        // Measured against the laid-out box, not the puzzle's grid, so the
        // wave still starts where the board visually centres.
        let centerRow = Double(layout.firstRow) + Double(layout.rows) / 2
        let centerCol = Double(layout.firstCol) + Double(layout.cols) / 2
        let distance = abs(Double(island.position.row) - centerRow)
            + abs(Double(island.position.col) - centerCol)
        return distance * Motion.boardEntranceStagger
    }

    // MARK: - Gesture

    private func boardGesture(_ layout: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = layout.island(at: value.startLocation, in: game.puzzle)
                }
                guard let origin = dragOrigin else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard hypot(dx, dy) >= 12 else {
                    ghostEdge = nil
                    return
                }
                // A real drag selects its origin (shows the corridor glow);
                // a plain tap leaves selection to `onTapIsland`, so tapping
                // doesn't pre-select and then instantly toggle back off.
                if game.selected != origin {
                    game.selected = origin
                }
                let direction: Direction = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                let target = game.dragTarget(from: origin, direction: direction)
                if target == nil && ghostEdge != nil {
                    ghostEdge = nil
                }
                ghostEdge = target
            }
            .onEnded { value in
                defer {
                    dragOrigin = nil
                    ghostEdge = nil
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let dragged = hypot(dx, dy) >= 12

                if let origin = dragOrigin, dragged {
                    if let edge = ghostEdge {
                        onCycleEdge(edge)
                    } else {
                        reject(origin)
                    }
                    return
                }
                // Tap: island first, then corridor.
                if let island = layout.island(at: value.location, in: game.puzzle) {
                    onTapIsland(island)
                } else if let edge = layout.edge(at: value.location, in: game.puzzle) {
                    if game.board.bridges[edge] == 0
                        && game.board.isBlocked(edge: edge, puzzle: game.puzzle) {
                        reject(game.puzzle.edges[edge].a)
                    } else {
                        onCycleEdge(edge)
                    }
                } else {
                    game.selected = nil
                }
            }
    }

    private func reject(_ island: Int) {
        Haptics.error()
        rejectedIsland = island
        withAnimation(Motion.reject) {
            rejectedIsland = nil
        }
    }
}

/// One island disc: paper circle, capacity ring, numeral.
private struct IslandView: View {
    let island: Island
    let game: HashiGame
    let radius: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool
    let isWarning: Bool
    let isRejected: Bool
    let rippleHop: Int?
    let entranceDelay: TimeInterval
    let entranceDone: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var rippling = false

    private var count: Int { game.bridgeCount(at: island.id) }
    private var satisfied: Bool { game.isSatisfied(island.id) }
    private var overfilled: Bool { game.isOverfilled(island.id) }

    private var displayedNumber: Int {
        // Expert mode shows remaining capacity; never negative (overfill shows
        // the clue with the error tint instead of a confusing minus).
        if game.showRemainingCapacity && !overfilled {
            return max(0, game.remaining(at: island.id))
        }
        return island.clue
    }

    private var ringColor: Color {
        if overfilled || isWarning { return Theme.vermillion }
        if rippling { return Theme.foam }
        if satisfied { return Theme.foam }
        return Theme.bridge
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.island)
                .shadow(color: .black.opacity(0.10), radius: radius * 0.12, y: radius * 0.06)
            Circle()
                .stroke(Theme.islandRim, lineWidth: 1.5)
            // Capacity ring: fills clockwise as bridges attach.
            Circle()
                .trim(from: 0, to: min(1, CGFloat(count) / CGFloat(island.clue)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: max(2.5, radius * 0.14),
                                                      lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(max(1.5, radius * 0.08))
            if isSelected || isHighlighted {
                Circle()
                    .stroke(Theme.bridge, lineWidth: Metrics.selectionRing)
                    .padding(-max(2.5, radius * 0.16))
            }
            Text("\(displayedNumber)")
                .font(Theme.islandFont(size: radius * 1.05))
                .foregroundStyle(overfilled ? Theme.vermillion : Theme.inkOnIsland)
        }
        .frame(width: radius * 2, height: radius * 2)
        .scaleEffect(settleScale)
        .offset(x: isRejected ? 4 : 0)
        .opacity(entranceDone ? (satisfied && !isSelected ? 0.82 : 1) : 0)
        .offset(y: entranceDone ? 0 : 10)
        .animation(Motion.boardEntrance.delay(entranceDelay), value: entranceDone)
        .animation(Motion.islandSettle, value: satisfied)
        .animation(Motion.selection, value: isSelected)
        .onChange(of: satisfied) { _, now in
            guard now, !reduceMotion else { return }
            settled = true
            withAnimation(Motion.islandSettle) { settled = false }
        }
        .onChange(of: rippleHop) { _, hop in
            guard let hop else { rippling = false; return }
            let delay = reduceMotion ? 0 : Double(hop) * Motion.rippleStagger
            withAnimation(Motion.ripple.delay(delay)) { rippling = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Island \(island.clue), row \(island.position.row + 1), column \(island.position.col + 1)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var settleScale: CGFloat {
        settled ? 1.06 : 1
    }

    private var accessibilityValue: String {
        if overfilled { return "\(count) bridges, which is too many" }
        if satisfied { return "complete" }
        return "\(count) of \(island.clue) bridges"
    }
}
