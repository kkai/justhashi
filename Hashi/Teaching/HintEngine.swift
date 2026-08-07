import Foundation

enum HintLevel: Int, Comparable, Sendable {
    case nudge, technique, highlight, resolution

    static func < (lhs: HintLevel, rhs: HintLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Hint: Sendable, Equatable {
    let level: HintLevel
    let application: TechniqueApplication
    let text: String
    let highlightIslands: [Int]
    let highlightEdges: [Int]
    /// True when the hint points at a player mistake, not teaching.
    let isErrorHint: Bool
    /// True when the teaching ladder was withheld behind the unlock. The banner
    /// offers to unlock instead of escalating.
    ///
    /// Last, with a default, so every existing construction site stays
    /// source-compatible with the memberwise initialiser.
    var isLocked: Bool = false
}

/// How much the hint engine may give away.
///
/// `.errorsOnly` is the free tier: it still catches contradictions ("something
/// here is wrong"), but never names a technique or walks the escalation ladder.
nonisolated enum HintPolicy: Sendable {
    case errorsOnly
    case full
}

/// Escalating, context-aware hints. Errors first; then the next teachable step
/// from the logical solver, revealed a level at a time:
/// nudge (region) → technique (name + rule) → highlight → resolution.
@MainActor
struct HintEngine {

    /// `showErrors` mirrors the setting: when off, hints teach the next step
    /// and never point out contradictions.
    func hint(for game: HashiGame, mastery: MasteryTracker,
              showErrors: Bool = true, policy: HintPolicy = .full) -> Hint {
        if showErrors, var errorHint = errorHint(for: game, level: .nudge) {
            // Free players keep the error check. They do not keep the ladder
            // that narrows it to the exact corridor, so the hint is flagged
            // locked — otherwise the banner offers a "Tell me more" that
            // escalates to the same hint and visibly does nothing.
            if policy != .full { errorHint.isLocked = true }
            return errorHint
        }
        guard let chain = LogicalSolver.hintChain(puzzle: game.puzzle, board: game.board) else {
            return Hint(level: .nudge,
                        application: TechniqueApplication(technique: .fullIsland),
                        text: "Everything on the board checks out. Keep going.",
                        highlightIslands: [], highlightEdges: [], isErrorHint: false)
        }
        let step = chain.placing
        guard policy == .full else {
            // Withheld, so deliberately *without* recordHint: penalising the
            // mastery path for a hint the player never saw would quietly damage
            // their progress the moment they pay. The copy must also name no
            // technique — that is the thing being sold.
            return Hint(level: .nudge,
                        application: step,
                        text: "There's a move available on this board. Teaching hints name the "
                            + "technique and show you where it applies. They're part of the full game.",
                        highlightIslands: [], highlightEdges: [],
                        isErrorHint: false, isLocked: true)
        }
        mastery.recordHint(technique: step.technique, level: .nudge)
        return Hint(level: .nudge,
                    application: step,
                    text: TechniqueContent.nudge(for: step, puzzle: game.puzzle),
                    highlightIslands: [], highlightEdges: [], isErrorHint: false)
    }

    func escalate(_ hint: Hint, for game: HashiGame, mastery: MasteryTracker,
                  policy: HintPolicy = .full) -> Hint {
        // A locked hint never climbs the ladder; the banner offers the unlock.
        guard policy == .full, !hint.isLocked else { return hint }
        guard hint.level < .resolution else { return hint }
        let next = HintLevel(rawValue: hint.level.rawValue + 1) ?? .resolution
        if hint.isErrorHint {
            return errorHint(for: game, level: next) ?? hint
        }
        let step = hint.application
        mastery.recordHint(technique: step.technique, level: next)
        let text: String
        switch next {
        case .nudge:
            text = hint.text
        case .technique:
            text = TechniqueContent.rule(for: step.technique)
        case .highlight:
            text = TechniqueContent.detail(for: step, puzzle: game.puzzle)
        case .resolution:
            text = TechniqueContent.resolution(for: step, puzzle: game.puzzle)
        }
        let showFocus = next >= .highlight
        return Hint(level: next, application: step, text: text,
                    highlightIslands: showFocus ? step.focusIslands : [],
                    highlightEdges: showFocus ? step.focusEdges : [],
                    isErrorHint: false)
    }

    /// Wrong bridges take priority over teaching: region first, exact spot
    /// later. A bridge is wrong when it exceeds what the solution puts there.
    private func errorHint(for game: HashiGame, level: HintLevel) -> Hint? {
        let wrongEdges = game.puzzle.edges.indices.filter {
            game.board.bridges[$0] > game.puzzle.solution[$0]
        }
        guard let first = wrongEdges.first else { return nil }
        let edge = game.puzzle.edges[first]
        let region = [edge.a, edge.b]
        let text: String
        switch level {
        case .nudge, .technique:
            text = "One of the bridges around here doesn't belong. Check these islands before going further."
        case .highlight:
            text = "One of the highlighted corridors carries too much. Something has to come off."
        case .resolution:
            text = "This corridor carries more bridges than the solution allows. Tap it until it clears."
        }
        return Hint(level: level,
                    application: TechniqueApplication(technique: .fullIsland,
                                                      focusIslands: region,
                                                      focusEdges: [first]),
                    text: text,
                    highlightIslands: level >= .technique ? region : [],
                    highlightEdges: level >= .highlight ? [first] : [],
                    isErrorHint: true)
    }
}
