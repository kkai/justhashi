import Foundation

/// All teaching copy. Hints escalate nudge → rule → detail → resolution;
/// lessons and the learn menu pull `rule`/`summary` from here so the app
/// explains each idea with one consistent voice.
nonisolated enum TechniqueContent {

    /// One-line curriculum summary (learn menu rows).
    static func summary(for technique: Technique) -> String {
        switch technique {
        case .fullIsland:
            "When a number equals everything its island could ever hold, every corridor gets a double."
        case .onlyNeighbor:
            "One way out means every bridge goes that way."
        case .oneEachWay:
            "One short of full: at least one bridge in every direction."
        case .capacityCount:
            "Count what the other corridors can still carry — the rest is forced."
        case .isolationGuard:
            "Never finish a small group that would cut itself off."
        case .segmentLink:
            "A group with one way out must use it."
        case .oneStepContradiction:
            "Suppose a bridge is there. If that breaks the board, it isn't."
        case .deepContradiction:
            "Chase a what-if two steps before it breaks. Deep water."
        }
    }

    /// The named rule, stated fully (hint level 2).
    static func rule(for technique: Technique) -> String {
        switch technique {
        case .fullIsland:
            "Full Islands: a 4 in a corner, a 6 on an edge, an 8 in the middle — the number equals two bridges to every neighbor, so every corridor gets a double. No choices to make."
        case .onlyNeighbor:
            "Only Neighbor: when an island has a single usable corridor, all of its bridges must use it."
        case .oneEachWay:
            "One Each Way: a 3 in a corner, a 5 on an edge, a 7 in the middle is one short of full — every direction carries at least one bridge, even before you know which gets the double."
        case .capacityCount:
            "Counting: add up the most the other corridors could carry. Whatever the number still needs beyond that must go through the corridor that's left."
        case .isolationGuard:
            "Don't Cut Off: every island must reach every other. A bridge that completes a little group — like a 1 to a 1 — seals it off from the rest, so that bridge is never right."
        case .segmentLink:
            "Stay Connected: when a group of joined islands has exactly one corridor left to the outside, that corridor must carry a bridge — it's the group's only way to reach everyone else."
        case .oneStepContradiction:
            "What If: suppose a corridor holds a bridge, and check what follows. If an island overfills or a group seals itself off, the supposition was wrong — and now you know."
        case .deepContradiction:
            "Deep Water: the same what-if, chased further. Follow the forced moves two steps; if the board breaks anywhere down the line, the first supposition was wrong."
        }
    }

    /// Level-1 nudge: region, no technique name.
    static func nudge(for step: TechniqueApplication, puzzle: HashiPuzzle) -> String {
        switch step.technique {
        case .fullIsland:
            "One island here can take no choices at all — its number fills every corridor it has."
        case .onlyNeighbor:
            "An island has only one place left to send its bridges."
        case .oneEachWay:
            "An island is one short of full. That pins down more than it seems."
        case .capacityCount:
            "Count what one island's other corridors could still carry."
        case .isolationGuard:
            "Careful — one tempting bridge here would strand part of the board."
        case .segmentLink:
            "A connected group is running out of ways to reach the rest."
        case .oneStepContradiction, .deepContradiction:
            "Try supposing a bridge and see what breaks."
        }
    }

    /// Level-3 detail: the reasoning, aimed at the highlighted spot.
    static func detail(for step: TechniqueApplication, puzzle: HashiPuzzle) -> String {
        let clue = step.explanation.clue
        switch step.technique {
        case .fullIsland:
            let neighbors = step.explanation.neighborCount
            return neighbors == 1
                ? "This \(clue) has a single neighbor, and \(clue) is a full double bridge. Fill the corridor."
                : "This \(clue) has exactly \(neighbors) neighbors — \(clue) is two bridges to each of them. Fill every corridor with a double."
        case .onlyNeighbor:
            return "The highlighted island has one open corridor. Everything it still needs goes there."
        case .oneEachWay:
            return "This \(clue) is one bridge short of filling every corridor. Each direction gets at least one — only the double is still open."
        case .capacityCount:
            return "This \(clue)'s other corridors can't carry enough on their own. The highlighted corridor has to make up the difference."
        case .isolationGuard:
            return "Completing the highlighted corridor would satisfy this little group entirely — and seal it off from everything else. Cap it lower."
        case .segmentLink:
            return "The highlighted group has exactly one corridor to the outside. It must carry a bridge."
        case .oneStepContradiction, .deepContradiction:
            return "Suppose the highlighted corridor changed. Follow the forced moves — an island breaks. So it can't."
        }
    }

    /// Level-4 resolution: the concrete move.
    static func resolution(for step: TechniqueApplication, puzzle: HashiPuzzle) -> String {
        let placements = step.boundChanges.filter { $0.newMin > 0 }
        if placements.isEmpty {
            return "This corridor can now be ruled out. Play on with that knowledge."
        }
        let described = placements.prefix(2).map { change in
            let edge = puzzle.edges[change.edge]
            let a = puzzle.islands[edge.a]
            let b = puzzle.islands[edge.b]
            let count = change.newMin == 2 ? "a double bridge" : "a bridge"
            return "\(count) between the \(a.clue) and the \(b.clue)"
        }
        return "Draw " + described.joined(separator: ", and ") + ". Tap Apply and it's done."
    }

    /// Lesson titles, curriculum order.
    static func lessonTitle(for technique: Technique?) -> String {
        guard let technique else { return "How Hashi Works" }
        return technique.displayName
    }
}
