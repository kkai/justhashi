import Foundation
import Observation

/// One step of a scripted lesson.
enum TutorialStep: Equatable {
    /// Show a message; advances with the Next button.
    case say(String)
    /// Show a message while highlighting islands and corridors.
    case sayHighlighting(String, islands: [Int], edges: [Int])
    /// Lock input until the target corridor holds exactly `count` bridges.
    case requireBridge(String, edge: Int, count: Int)
    /// Free play until the puzzle is solved (the lesson's exam).
    case solveFreely(String)
    /// Completion beat.
    case celebrate(String)
}

struct TutorialLesson: Identifiable {
    let id: String
    /// nil for Lesson 0 (the rules); otherwise the technique taught.
    ///
    /// The lesson's title and one-line summary deliberately live in
    /// `TechniqueContent`, not here: the menu and the lesson screen both read
    /// them from there, so a second copy on this type could only drift.
    let technique: Technique?
    let puzzle: HashiPuzzle
    let steps: [TutorialStep]
}

/// Drives a lesson: exposes the current step, filters board input, advances
/// when step conditions are met. Input must come through `handleTapIsland`/
/// `handleCycleEdge` — a lesson that can be walked out from under (input the
/// script doesn't see) was Kakuro's hardest-won tutorial bug.
@Observable @MainActor
final class TutorialEngine {
    let lesson: TutorialLesson
    let game: HashiGame

    private(set) var stepIndex = 0
    private(set) var finished = false
    /// Set briefly when the player does something the step doesn't allow.
    private(set) var wiggle = false

    init(lesson: TutorialLesson) {
        self.lesson = lesson
        let profile = LogicalSolver.solve(lesson.puzzle).histogram
        let generated = GeneratedHashiPuzzle(puzzle: lesson.puzzle,
                                             difficulty: .easy,
                                             techniqueProfile: profile)
        self.game = HashiGame(puzzle: generated)
    }

    var currentStep: TutorialStep? {
        stepIndex < lesson.steps.count ? lesson.steps[stepIndex] : nil
    }

    var message: String {
        switch currentStep {
        case .say(let text), .sayHighlighting(let text, _, _),
             .requireBridge(let text, _, _), .solveFreely(let text),
             .celebrate(let text):
            text
        case nil:
            ""
        }
    }

    var highlightedIslands: Set<Int> {
        switch currentStep {
        case .sayHighlighting(_, let islands, _):
            Set(islands)
        case .requireBridge(_, let edge, _):
            [game.puzzle.edges[edge].a, game.puzzle.edges[edge].b]
        default:
            []
        }
    }

    var highlightedEdges: Set<Int> {
        switch currentStep {
        case .sayHighlighting(_, _, let edges):
            Set(edges)
        case .requireBridge(_, let edge, _):
            [edge]
        default:
            []
        }
    }

    /// Steps that advance via the Next button (no player action needed).
    var showsNextButton: Bool {
        switch currentStep {
        case .say, .sayHighlighting, .celebrate: true
        default: false
        }
    }

    func next() {
        guard showsNextButton else { return }
        if case .celebrate = currentStep {
            finished = true
        }
        advance()
    }

    // MARK: - Filtered input from the board

    func handleTapIsland(_ island: Int) {
        switch currentStep {
        case .requireBridge(_, let edge, _):
            // Selecting either endpoint is harmless and shows the glow.
            let e = game.puzzle.edges[edge]
            if island == e.a || island == e.b {
                game.tapIsland(island)
            } else {
                reject()
            }
        case .solveFreely:
            game.tapIsland(island)
        default:
            reject()
        }
    }

    func handleCycleEdge(_ edge: Int) {
        switch currentStep {
        case .requireBridge(_, let target, let count):
            guard edge == target else { reject(); return }
            let outcome = game.cycleBridge(edge: edge)
            playFeedback(outcome)
            if game.board.bridges[edge] == count {
                advance()
            }
        case .solveFreely:
            let outcome = game.cycleBridge(edge: edge)
            playFeedback(outcome)
            if game.phase == .won {
                advance()
            }
        default:
            reject()
        }
    }

    private func playFeedback(_ outcome: HashiGame.CycleOutcome) {
        switch outcome {
        case .drewSingle: Haptics.bridge()
        case .drewDouble: Haptics.bridgeDouble()
        case .cleared: Haptics.clear()
        case .blocked: Haptics.error()
        }
    }

    private func advance() {
        stepIndex += 1
        if case .requireBridge(_, let edge, _) = currentStep {
            // Prime the selection so the corridor glows.
            game.selected = game.puzzle.edges[edge].a
        }
        if currentStep == nil {
            finished = true
        }
    }

    private func reject() {
        Haptics.error()
        wiggle = true
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            wiggle = false
        }
    }
}
