import Foundation
import Observation

/// The one stateful game object: puzzle + player bridges + undo + timer.
@Observable @MainActor
final class HashiGame {
    enum Phase: String, Codable {
        case playing, paused, won
    }

    /// What a cycle attempt did — the view maps this to haptics/animation.
    enum CycleOutcome {
        case drewSingle, drewDouble, cleared, blocked
    }

    let generated: GeneratedHashiPuzzle
    var puzzle: HashiPuzzle { generated.puzzle }

    private(set) var board: HashiBoardState
    private(set) var undoStack: [Move] = []
    private(set) var phase: Phase = .playing
    private(set) var elapsed: TimeInterval = 0
    /// Island the player tapped (shows the capacity callout + corridor glow).
    var selected: Int?
    /// Display flag mirrored from settings: show remaining capacity instead of
    /// the clue on island discs.
    var showRemainingCapacity = false

    /// Board state immediately before the most recent move. Mastery tracking
    /// needs it to ask "would the solver have made this move?".
    private(set) var boardBeforeLastMove: HashiBoardState?

    private var lastTick: Date?

    /// The difficulty the player asked for, which is not always the one they
    /// got: `generate` returns the nearest band when its candidate budget runs
    /// out. Stats key on this so a best time lands in the column the player
    /// actually chose. Optional so old saves still decode.
    let requestedDifficulty: Difficulty?

    /// Set when this game is a daily puzzle — a win then feeds the streak.
    let dailyKey: DayKey?

    var difficultyForRecords: Difficulty { requestedDifficulty ?? generated.difficulty }

    init(puzzle: GeneratedHashiPuzzle, requestedDifficulty: Difficulty? = nil,
         dailyKey: DayKey? = nil) {
        self.generated = puzzle
        self.requestedDifficulty = requestedDifficulty
        self.dailyKey = dailyKey
        board = HashiBoardState(edgeCount: puzzle.puzzle.edges.count)
    }

    // MARK: - Input

    var canUndo: Bool { !undoStack.isEmpty }

    func tapIsland(_ island: Int) {
        selected = (selected == island) ? nil : island
    }

    /// Cycles a corridor 0 → 1 → 2 → 0. Crossing-blocked corridors are
    /// rejected — the UI wiggles instead of drawing an illegal bridge.
    @discardableResult
    func cycleBridge(edge: Int) -> CycleOutcome {
        guard phase == .playing else { return .blocked }
        let current = board.bridges[edge]
        if current == 0 && board.isBlocked(edge: edge, puzzle: puzzle) {
            return .blocked
        }
        let next = (current + 1) % 3
        perform(.setBridge(edge: edge, old: current, new: next))
        checkWin()
        switch next {
        case 1: return .drewSingle
        case 2: return .drewDouble
        default: return .cleared
        }
    }

    /// The corridor a drag from `island` toward `direction` would affect,
    /// nil when no corridor exists there or it is crossing-blocked while empty.
    func dragTarget(from island: Int, direction: Direction) -> Int? {
        guard let edge = puzzle.edge(from: island, direction: direction) else { return nil }
        if board.bridges[edge] == 0 && board.isBlocked(edge: edge, puzzle: puzzle) {
            return nil
        }
        return edge
    }

    func undo() {
        guard phase == .playing, let inverse = undoStack.popLast() else { return }
        inverse.apply(to: &board)
    }

    // MARK: - Queries for the UI

    func bridgeCount(at island: Int) -> Int {
        board.bridgeCount(at: island, puzzle: puzzle)
    }

    func remaining(at island: Int) -> Int {
        puzzle.islands[island].clue - bridgeCount(at: island)
    }

    func isSatisfied(_ island: Int) -> Bool {
        remaining(at: island) == 0
    }

    func isOverfilled(_ island: Int) -> Bool {
        remaining(at: island) < 0
    }

    /// Corridors that could legally take another bridge from this island.
    func openCorridors(from island: Int) -> [Int] {
        puzzle.edgesAt[island].filter { edge in
            board.bridges[edge] < 2
                && !(board.bridges[edge] == 0 && board.isBlocked(edge: edge, puzzle: puzzle))
        }
    }

    /// The beginner trap surfaced: a fully-satisfied group that excludes
    /// islands. Returns its islands for warning shading, nil when fine.
    func satisfiedIsolatedComponent() -> [Int]? {
        let components = board.components(puzzle: puzzle)
        guard components.count > 1 else { return nil }
        for component in components where component.count > 1 {
            if component.allSatisfy({ isSatisfied($0) }) {
                return component
            }
        }
        return nil
    }

    /// Auto-completes islands the first two curriculum techniques force, as
    /// one undoable batch. Setting-gated by the caller; deliberately limited to
    /// `fullIsland` and `onlyNeighbor` so it never leaks harder deductions.
    func autoCompleteForcedIslands() {
        guard phase == .playing else { return }
        var state = LogicalSolver.State(puzzle: puzzle, board: board)
        var moves: [Move] = []
        var guardCounter = 0
        while guardCounter < 64 {
            guardCounter += 1
            let step = LogicalSolver.detectFullIsland(puzzle, state)
                ?? LogicalSolver.detectOnlyNeighbor(puzzle, state)
            guard let step else { break }
            LogicalSolver.apply(step, to: &state, puzzle: puzzle)
            for change in step.boundChanges where Int(change.newMin) > board.bridges[change.edge] {
                let old = moves.reduce(board.bridges[change.edge]) { value, move in
                    if case let .setBridge(edge, _, new) = move, edge == change.edge { return new }
                    return value
                }
                if Int(change.newMin) > old {
                    moves.append(.setBridge(edge: change.edge, old: old, new: Int(change.newMin)))
                }
            }
        }
        guard !moves.isEmpty else { return }
        perform(.batch(moves))
        checkWin()
    }

    /// Applies a hint's forced bridges as one undoable batch.
    func apply(_ application: TechniqueApplication) {
        guard phase == .playing else { return }
        var moves: [Move] = []
        for change in application.boundChanges where Int(change.newMin) > board.bridges[change.edge] {
            moves.append(.setBridge(edge: change.edge,
                                    old: board.bridges[change.edge],
                                    new: Int(change.newMin)))
        }
        guard !moves.isEmpty else { return }
        perform(moves.count == 1 ? moves[0] : .batch(moves))
        checkWin()
    }

    // MARK: - Mastery

    /// Edges that have already earned mastery credit in this game.
    /// Undo deliberately does not clear these — place/undo/replace looks
    /// identical to a fresh deduction, so without this a player could farm a
    /// technique to "Learned" by tapping undo in a loop.
    private var creditedEdges: Set<Int> = []

    func claimMasteryCredit(edge: Int) -> Bool {
        creditedEdges.insert(edge).inserted
    }

    // MARK: - Win ripple

    /// BFS hop distance of every island from the given island, over placed
    /// bridges — drives the win ripple's stagger.
    func rippleDistances(from origin: Int) -> [Int: Int] {
        var distances: [Int: Int] = [origin: 0]
        var frontier = [origin]
        var hop = 0
        while !frontier.isEmpty {
            hop += 1
            var next: [Int] = []
            for island in frontier {
                for edge in puzzle.edgesAt[island] where board.bridges[edge] > 0 {
                    let neighbor = puzzle.neighbor(of: island, via: edge)
                    if distances[neighbor] == nil {
                        distances[neighbor] = hop
                        next.append(neighbor)
                    }
                }
            }
            frontier = next
        }
        return distances
    }

    /// The island the last move touched — the ripple's origin.
    var lastMoveIsland: Int? {
        guard let last = undoStack.last else { return nil }
        func firstEdge(of move: Move) -> Int? {
            switch move {
            case let .setBridge(edge, _, _): edge
            case let .batch(moves): moves.compactMap(firstEdge).first
            }
        }
        guard let edge = firstEdge(of: last) else { return nil }
        return puzzle.edges[edge].a
    }

    // MARK: - Timer

    func tick(now: Date = .now) {
        guard phase == .playing else { lastTick = nil; return }
        if let last = lastTick {
            elapsed += now.timeIntervalSince(last)
        }
        lastTick = now
    }

    func pause() {
        if phase == .playing { phase = .paused; lastTick = nil }
    }

    func resume() {
        if phase == .paused { phase = .playing }
    }

    // MARK: - Save / restore

    struct Snapshot: Codable {
        let generated: GeneratedHashiPuzzle
        let board: HashiBoardState
        let undoStack: [Move]
        let elapsed: TimeInterval
        var requestedDifficulty: Difficulty?
        var dailyKey: DayKey?
    }

    var snapshot: Snapshot {
        Snapshot(generated: generated, board: board, undoStack: undoStack,
                 elapsed: elapsed, requestedDifficulty: requestedDifficulty,
                 dailyKey: dailyKey)
    }

    convenience init(snapshot: Snapshot) {
        self.init(puzzle: snapshot.generated,
                  requestedDifficulty: snapshot.requestedDifficulty,
                  dailyKey: snapshot.dailyKey)
        board = snapshot.board
        undoStack = snapshot.undoStack
        elapsed = snapshot.elapsed
    }

    // MARK: - Private

    private func perform(_ move: Move) {
        boardBeforeLastMove = board
        let inverse = move.apply(to: &board)
        undoStack.append(inverse)
    }

    private func checkWin() {
        if board.isSolved(for: puzzle) {
            phase = .won
            lastTick = nil
            selected = nil
        }
    }
}
