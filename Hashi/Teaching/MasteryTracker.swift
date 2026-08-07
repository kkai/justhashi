import Foundation
import Observation

/// Tracks how well the player knows each technique, Good Sudoku-style:
/// unaided applications advance mastery, hints delay it.
@Observable @MainActor
final class MasteryTracker {

    enum MasteryState: String, Codable, Comparable {
        case locked, introduced, practicing, learned

        private var order: Int {
            switch self {
            case .locked: 0
            case .introduced: 1
            case .practicing: 2
            case .learned: 3
            }
        }

        static func < (lhs: MasteryState, rhs: MasteryState) -> Bool {
            lhs.order < rhs.order
        }
    }

    struct Record: Codable, Equatable {
        var state: MasteryState = .locked
        var unaidedUses = 0
        var hintedUses = 0
        var drillsCompleted = 0
        var lessonCompleted = false
    }

    /// Unaided applications needed to reach `.learned`.
    static let learnedThreshold = 5

    private(set) var records: [Technique: Record] = [:]
    private let store: ProgressStore?

    init(store: ProgressStore? = nil) {
        self.store = store
        if let saved = store?.loadMastery([Technique: Record].self) {
            records = saved
        } else {
            // The first two techniques start available; the rest unlock in order.
            records[.fullIsland] = Record(state: .introduced)
            records[.onlyNeighbor] = Record(state: .introduced)
        }
    }

    func record(for technique: Technique) -> Record {
        records[technique] ?? Record()
    }

    func state(of technique: Technique) -> MasteryState {
        record(for: technique).state
    }

    // MARK: - Events

    /// The player asked for a hint on this technique.
    func recordHint(technique: Technique, level: HintLevel) {
        var rec = record(for: technique)
        if rec.state == .locked { rec.state = .introduced }
        if level >= .highlight {
            rec.hintedUses += 1
        }
        records[technique] = rec
        persist()
    }

    /// The player drew a bridge; if it matches what the solver's deduction
    /// chain was about to force, that counts as an application. The chain's
    /// **hardest technique by rater weight** gets the credit — the player who
    /// drew this bridge had to do every deduction in the chain, and the
    /// binding constraint is the one that earned it.
    ///
    /// `unaided` is the caller's to declare, not something this can infer: a
    /// bridge drawn by tapping Apply on a hint is indistinguishable here from
    /// one the player worked out.
    func recordBridge(edge: Int, game: HashiGame, unaided: Bool = true) {
        guard unaided else { return }
        let value = game.board.bridges[edge]
        guard value > 0,
              game.puzzle.solution[edge] >= value,
              let previous = game.boardBeforeLastMove,
              previous.bridges[edge] < value
        else { return }
        guard let chain = LogicalSolver.hintChain(puzzle: game.puzzle, board: previous) else {
            return
        }
        // Credit only when the chain's placing step forces this exact edge to
        // at least the played value — if the solver's next placement is
        // elsewhere, the move may have been a guess.
        let forcesThis = chain.placing.boundChanges.contains {
            $0.edge == edge && Int($0.newMin) >= value
        }
        guard forcesThis else { return }
        let hardest = chain.steps.map(\.technique).max {
            DifficultyRater.weight($0) < DifficultyRater.weight($1)
        }
        advance(technique: hardest ?? chain.placing.technique)
    }

    func recordLessonCompleted(_ technique: Technique) {
        var rec = record(for: technique)
        rec.lessonCompleted = true
        if rec.state < .practicing { rec.state = .practicing }
        records[technique] = rec
        introduceEarlier(than: technique)
        unlockNext(after: technique)
        persist()
    }

    func recordDrillCompleted(_ technique: Technique, unaided: Bool) {
        var rec = record(for: technique)
        rec.drillsCompleted += 1
        if unaided { rec.unaidedUses += 1 }
        records[technique] = rec
        introduceEarlier(than: technique)
        promoteIfEarned(technique)
        persist()
    }

    private func advance(technique: Technique) {
        var rec = record(for: technique)
        rec.unaidedUses += 1
        if rec.state == .locked { rec.state = .introduced }
        records[technique] = rec
        introduceEarlier(than: technique)
        promoteIfEarned(technique)
        persist()
    }

    /// The curriculum is a ladder, and a ladder cannot have holes. Play can
    /// credit a technique the player never formally reached — the hint chain
    /// credits its hardest step — which would otherwise leave an *earlier*
    /// lesson locked while a later one is open, and the Practice list reads as
    /// broken.
    private func introduceEarlier(than technique: Technique) {
        for earlier in Technique.allCases where earlier < technique {
            var rec = record(for: earlier)
            if rec.state == .locked {
                rec.state = .introduced
                records[earlier] = rec
            }
        }
    }

    private func promoteIfEarned(_ technique: Technique) {
        var rec = record(for: technique)
        if rec.unaidedUses >= Self.learnedThreshold, rec.state < .learned {
            rec.state = .learned
            records[technique] = rec
            unlockNext(after: technique)
        }
    }

    private func unlockNext(after technique: Technique) {
        guard let next = Technique(rawValue: technique.rawValue + 1) else { return }
        var rec = record(for: next)
        if rec.state == .locked {
            rec.state = .introduced
            records[next] = rec
        }
    }

    private func persist() {
        store?.saveMastery(records)
    }
}
