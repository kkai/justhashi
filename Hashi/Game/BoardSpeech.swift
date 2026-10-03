import SwiftUI

/// Everything VoiceOver says about the board. Bridges are drawn, not views,
/// so speech carries what sight gets from the water: where the corridors go,
/// what a move did, and what a hint is pointing at.
enum BoardSpeech {

    static func island(_ island: Island) -> String {
        "the \(island.clue) at row \(island.position.row + 1), column \(island.position.col + 1)"
    }

    /// Where `other` lies seen from `island`: "on the right", "above".
    static func side(of other: Island, from island: Island) -> String {
        if other.position.row == island.position.row {
            return other.position.col > island.position.col ? "on the right" : "on the left"
        }
        return other.position.row > island.position.row ? "below" : "above"
    }

    /// The action that cycles `edge` from `island`, named for what it does.
    /// Nil when the corridor is empty and crossed by a bridge.
    static func actionName(edge: Edge, from island: Island, game: HashiGame) -> String? {
        let other = game.puzzle.islands[edge.other(island.id)]
        let target = "the \(other.clue) \(side(of: other, from: island))"
        switch game.board.bridges[edge.id] {
        case 0:
            return game.dragTarget(from: island.id, direction: direction(of: other, from: island)) == nil
                ? nil : "Add a bridge to \(target)"
        case 1: return "Make the bridge to \(target) double"
        default: return "Remove the bridges to \(target)"
        }
    }

    static func direction(of other: Island, from island: Island) -> Direction {
        if other.position.row == island.position.row {
            return other.position.col > island.position.col ? .right : .left
        }
        return other.position.row > island.position.row ? .down : .up
    }

    /// What a bridge move did, for a player who can't see it drawn.
    static func edgeChanged(_ edge: Edge, before: Int, game: HashiGame) -> String {
        let a = game.puzzle.islands[edge.a], b = game.puzzle.islands[edge.b]
        let now = game.board.bridges[edge.id]
        guard now != before else { return "Not allowed here" }
        let between = "between \(island(a)) and \(island(b))"
        var parts = [now == 0 ? "Bridges removed \(between)"
                     : now == 1 ? "Single bridge \(between)" : "Double bridge \(between)"]
        for end in [a, b] {
            if game.isOverfilled(end.id) {
                parts.append("The \(end.clue) has too many bridges")
            } else if game.isSatisfied(end.id) {
                parts.append("The \(end.clue) is complete")
            }
        }
        return parts.joined(separator: ". ")
    }

    /// The hint as shown, plus where it points: hint text says "the
    /// highlighted island"; this names it.
    static func spokenHint(_ hint: Hint, puzzle: HashiPuzzle?) -> String {
        guard let puzzle else { return hint.text }
        var parts = [hint.text]
        let islands = hint.highlightIslands.prefix(4).map { island(puzzle.islands[$0]) }
        if !islands.isEmpty { parts.append("Highlighted: " + islands.joined(separator: "; ") + ".") }
        if hint.level == .resolution, !hint.isErrorHint {
            let changes = hint.application.boundChanges.compactMap { change -> String? in
                guard change.edge < puzzle.edges.count else { return nil }
                let edge = puzzle.edges[change.edge]
                let count = change.newMin == change.newMax
                    ? (change.newMin == 0 ? "no bridge" : change.newMin == 1 ? "1 bridge" : "2 bridges")
                    : "at least \(change.newMin) \(change.newMin == 1 ? "bridge" : "bridges")"
                return "\(count) from \(island(puzzle.islands[edge.a])) to \(island(puzzle.islands[edge.b]))"
            }
            if !changes.isEmpty { parts.append("Bridges: " + changes.joined(separator: "; ") + ".") }
        }
        return parts.joined(separator: " ")
    }

    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
