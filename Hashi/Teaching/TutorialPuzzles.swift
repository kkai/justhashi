import Foundation

/// Hand-authored lesson boards and scripts. **Never route a lesson through the
/// generator** — every board here is baked, proven unique by
/// `TutorialFixtureTests`, and its scripts are walked programmatically by the
/// same suite so the content cannot drift from the engine.
///
/// `bakedTechniques` is the source of truth for which lessons exist.
nonisolated enum TutorialPuzzles {

    /// Lesson 0 (rules, technique nil) plus one lesson per technique.
    static let bakedTechniques: [Technique?] = [nil] + Technique.allCases.map { $0 }

    @MainActor
    static func lesson(for technique: Technique?) -> TutorialLesson {
        switch technique {
        case nil: rulesLesson()
        case .fullIsland: fullIslandLesson()
        case .onlyNeighbor: onlyNeighborLesson()
        case .oneEachWay: oneEachWayLesson()
        case .capacityCount: capacityCountLesson()
        case .isolationGuard: isolationGuardLesson()
        case .segmentLink: segmentLinkLesson()
        case .oneStepContradiction: oneStepLesson()
        case .deepContradiction: deepWaterLesson()
        }
    }

    /// Edge id between two islands — scripts reference corridors this way so
    /// they can never drift from `HashiPuzzle.build`'s edge ordering.
    static func edge(_ puzzle: HashiPuzzle, _ a: Int, _ b: Int) -> Int {
        puzzle.edges.first { PairKey($0.a, $0.b) == PairKey(a, b) }!.id
    }

    // MARK: - Lesson 0: the rules

    /// ```
    /// 2 . 4 . 1
    ///     |
    /// . . 1 . .
    /// ```
    static let rulesBoard = HashiPuzzle.build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),   // 0
            (GridPosition(row: 0, col: 2), 4),   // 1
            (GridPosition(row: 0, col: 4), 1),   // 2
            (GridPosition(row: 2, col: 2), 1),   // 3
        ],
        bridgeNetwork: [PairKey(0, 1): 2, PairKey(1, 2): 1, PairKey(1, 3): 1]
    )

    private static func rulesLesson() -> TutorialLesson {
        let p = rulesBoard
        return TutorialLesson(
            id: "rules", technique: nil,
            title: "How Hashi Works",
            summary: "Bridges, doubles, and one connected world.",
            puzzle: p,
            steps: [
                .say("Hashi is played on islands. Each number says exactly how many bridges touch that island — no more, no fewer."),
                .sayHighlighting("Bridges run along these corridors: straight lines, up-down or left-right, never diagonal.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .requireBridge("Drag from the 2 toward the 4 to draw your first bridge.",
                               edge: edge(p, 0, 1), count: 1),
                .requireBridge("A corridor can carry a second bridge. Drag the same way again to make it a double.",
                               edge: edge(p, 0, 1), count: 2),
                .say("That double finishes the 2 — its ring is full. Watch the rings: they show how much each island still needs."),
                .requireBridge("The 1 on the right needs a single bridge. Connect it to the 4.",
                               edge: edge(p, 1, 2), count: 1),
                .requireBridge("One more: link the 4 down to the last island.",
                               edge: edge(p, 1, 3), count: 1),
                .say("Two more rules and you know everything. Bridges may never cross each other — the app simply won't draw an illegal one."),
                .celebrate("And every island must join one connected network — no separate groups. That's Hashi. Let's learn to solve it well."),
            ]
        )
    }

    // MARK: - Technique lessons

    /// ```
    /// 4 . 4
    /// .   .
    /// 4 . 4
    /// ```
    static let fullIslandBoard = HashiPuzzle.build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 4),
            (GridPosition(row: 0, col: 2), 4),
            (GridPosition(row: 2, col: 0), 4),
            (GridPosition(row: 2, col: 2), 4),
        ],
        bridgeNetwork: [PairKey(0, 1): 2, PairKey(0, 2): 2,
                        PairKey(1, 3): 2, PairKey(2, 3): 2]
    )

    private static func fullIslandLesson() -> TutorialLesson {
        let p = fullIslandBoard
        return TutorialLesson(
            id: "fullIsland", technique: .fullIsland,
            title: "Full Islands",
            summary: "4 in a corner, 6 on an edge, 8 in the middle: no choices at all.",
            puzzle: p,
            steps: [
                .sayHighlighting("This 4 sits in a corner. It has exactly two corridors — and 4 is two bridges in each. There is nothing to decide.",
                                 islands: [0], edges: [edge(p, 0, 1), edge(p, 0, 2)]),
                .requireBridge("Give the top corridor its double.", edge: edge(p, 0, 1), count: 2),
                .requireBridge("And the left corridor too.", edge: edge(p, 0, 2), count: 2),
                .say("A corner 4, an edge 6, a middle 8 — whenever the number equals two bridges to every neighbor, fill everything. Free moves."),
                .solveFreely("Every island here is full. Finish the board."),
                .celebrate("Full Islands: the fastest opening in Hashi. Scan for them first, every game."),
            ]
        )
    }

    /// `1 . 3 . 3 . 1`
    static let onlyNeighborBoard = HashiPuzzle.build(
        rows: 1, cols: 7,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 1),
            (GridPosition(row: 0, col: 2), 3),
            (GridPosition(row: 0, col: 4), 3),
            (GridPosition(row: 0, col: 6), 1),
        ],
        bridgeNetwork: [PairKey(0, 1): 1, PairKey(1, 2): 2, PairKey(2, 3): 1]
    )

    private static func onlyNeighborLesson() -> TutorialLesson {
        let p = onlyNeighborBoard
        return TutorialLesson(
            id: "onlyNeighbor", technique: .onlyNeighbor,
            title: "Only Neighbor",
            summary: "One way out means every bridge goes that way.",
            puzzle: p,
            steps: [
                .sayHighlighting("This 1 has a single neighbor. Wherever its bridge goes, there's only one place it can go.",
                                 islands: [0], edges: [edge(p, 0, 1)]),
                .requireBridge("Connect the 1 to its only neighbor.", edge: edge(p, 0, 1), count: 1),
                .sayHighlighting("Now look at the 3 you just touched: one bridge placed, and only one open corridor left. The remaining two bridges are forced.",
                                 islands: [1], edges: [edge(p, 1, 2)]),
                .requireBridge("Draw the double.", edge: edge(p, 1, 2), count: 2),
                .solveFreely("Finish the chain."),
                .celebrate("Only Neighbor: when there's one road, take it — with everything you've got."),
            ]
        )
    }

    /// ```
    /// 3 . 2 . 1
    /// |       |
    /// 2 . . . 2
    /// ```
    static let oneEachWayBoard = HashiPuzzle.build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 3),   // 0
            (GridPosition(row: 0, col: 2), 2),   // 1
            (GridPosition(row: 0, col: 4), 1),   // 2
            (GridPosition(row: 2, col: 0), 2),   // 3
            (GridPosition(row: 2, col: 4), 2),   // 4
        ],
        bridgeNetwork: [PairKey(0, 1): 2, PairKey(1, 2): 0, PairKey(0, 3): 1,
                        PairKey(2, 4): 1, PairKey(3, 4): 1]
    )

    private static func oneEachWayLesson() -> TutorialLesson {
        let p = oneEachWayBoard
        return TutorialLesson(
            id: "oneEachWay", technique: .oneEachWay,
            title: "One Each Way",
            summary: "One short of full still pins every direction.",
            puzzle: p,
            steps: [
                .sayHighlighting("This corner 3 could hold at most 4 — a double each way. Three is one short of that. So each corridor carries at least one; only where the double goes is open.",
                                 islands: [0], edges: [edge(p, 0, 1), edge(p, 0, 3)]),
                .requireBridge("Place the guaranteed bridge toward the 2.", edge: edge(p, 0, 1), count: 1),
                .requireBridge("And the guaranteed bridge going down.", edge: edge(p, 0, 3), count: 1),
                .say("The same idea works for a 5 on an edge and a 7 in the middle: one short of full means at least one bridge in every direction."),
                .solveFreely("Use what you know to finish the board."),
                .celebrate("One Each Way: partial certainty is still certainty. Bank the guaranteed bridges early."),
            ]
        )
    }

    /// `1 . 3 . 2`
    static let capacityBoard = HashiPuzzle.build(
        rows: 1, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 1),
            (GridPosition(row: 0, col: 2), 3),
            (GridPosition(row: 0, col: 4), 2),
        ],
        bridgeNetwork: [PairKey(0, 1): 1, PairKey(1, 2): 2]
    )

    private static func capacityCountLesson() -> TutorialLesson {
        let p = capacityBoard
        return TutorialLesson(
            id: "capacityCount", technique: .capacityCount,
            title: "Counting",
            summary: "What the other corridors can't carry, this one must.",
            puzzle: p,
            steps: [
                .sayHighlighting("The middle island needs 3. Its left neighbor is a 1 — that corridor can never carry more than one bridge.",
                                 islands: [1, 0], edges: [edge(p, 0, 1)]),
                .sayHighlighting("Count: 3 needed, at most 1 from the left. At least 2 must go right. The double is forced before you know anything else.",
                                 islands: [1, 2], edges: [edge(p, 1, 2)]),
                .requireBridge("Draw the forced double.", edge: edge(p, 1, 2), count: 2),
                .solveFreely("Finish the row."),
                .celebrate("Counting: add up what the other corridors could carry. The shortfall belongs to the one that's left."),
            ]
        )
    }

    /// ```
    /// 1 . 1
    /// .   .
    /// 2 . 2
    /// ```
    static let isolationBoard = HashiPuzzle.build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 1),
            (GridPosition(row: 0, col: 2), 1),
            (GridPosition(row: 2, col: 0), 2),
            (GridPosition(row: 2, col: 2), 2),
        ],
        bridgeNetwork: [PairKey(0, 2): 1, PairKey(1, 3): 1, PairKey(2, 3): 1]
    )

    private static func isolationGuardLesson() -> TutorialLesson {
        let p = isolationBoard
        return TutorialLesson(
            id: "isolationGuard", technique: .isolationGuard,
            title: "Don't Cut Off",
            summary: "A finished little group is a stranded one.",
            puzzle: p,
            steps: [
                .sayHighlighting("Two 1s, side by side. A single bridge between them would satisfy both — tempting.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("But finished islands take no more bridges. Those two would be sealed off — an island pair adrift, cut off from everything else. The rule says one connected world, so that bridge is never right."),
                .requireBridge("Send the left 1 downward instead.", edge: edge(p, 0, 2), count: 1),
                .requireBridge("And the right 1 down too.", edge: edge(p, 1, 3), count: 1),
                .solveFreely("Connect what remains."),
                .celebrate("Don't Cut Off: before completing a small group, ask who gets left outside. 1–1 and 2–2 pairs are the classic traps."),
            ]
        )
    }

    /// ```
    /// 2 . . . 2
    /// |       |
    /// 1 . . . 1
    /// ```
    static let segmentBoard = HashiPuzzle.build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),   // 0 X
            (GridPosition(row: 0, col: 4), 2),   // 1 Y
            (GridPosition(row: 2, col: 0), 1),   // 2 W
            (GridPosition(row: 2, col: 4), 1),   // 3 V
        ],
        bridgeNetwork: [PairKey(0, 1): 1, PairKey(0, 2): 1,
                        PairKey(1, 3): 1, PairKey(2, 3): 0]
    )

    private static func segmentLinkLesson() -> TutorialLesson {
        let p = segmentBoard
        return TutorialLesson(
            id: "segmentLink", technique: .segmentLink,
            title: "Stay Connected",
            summary: "A group with one way out must use it.",
            puzzle: p,
            steps: [
                .sayHighlighting("Suppose the top pair were joined by a double — both 2s full. The bottom islands could still pair up below… and the board would split in two.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("Whenever a group of joined islands is down to one corridor that reaches the outside, that corridor must carry a bridge. A group that spends its last exit on itself is stranded."),
                .requireBridge("Join the top islands with a single bridge — they'll each keep one corridor free.",
                               edge: edge(p, 0, 1), count: 1),
                .requireBridge("Now spend the left 2's last bridge on its way out, down to the 1.",
                               edge: edge(p, 0, 2), count: 1),
                .solveFreely("Finish the board — keep everyone connected."),
                .celebrate("Stay Connected: watch each group's exits. When only one remains, it's not optional."),
            ]
        )
    }

    /// ```
    /// 2 . 2
    /// .   .
    /// 2 . 2
    /// ```
    static let whatIfBoard = HashiPuzzle.build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),
            (GridPosition(row: 0, col: 2), 2),
            (GridPosition(row: 2, col: 0), 2),
            (GridPosition(row: 2, col: 2), 2),
        ],
        bridgeNetwork: [PairKey(0, 1): 1, PairKey(0, 2): 1,
                        PairKey(1, 3): 1, PairKey(2, 3): 1]
    )

    private static func oneStepLesson() -> TutorialLesson {
        let p = whatIfBoard
        return TutorialLesson(
            id: "oneStepContradiction", technique: .oneStepContradiction,
            title: "What If",
            summary: "Suppose a bridge. If the board breaks, it isn't there.",
            puzzle: p,
            steps: [
                .sayHighlighting("Four 2s in a ring. Nothing is forced by counting alone — so suppose something. What if the top corridor held a double?",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("Then both top 2s would be full — and sealed off from the bottom pair. Broken board. So the supposition is wrong: the top corridor holds at most one bridge. Every corridor here reasons the same way."),
                .requireBridge("Place a single on the top corridor.", edge: edge(p, 0, 1), count: 1),
                .solveFreely("Each corridor carries exactly one. Close the ring."),
                .celebrate("What If: a supposition you can refute is knowledge you can keep. One step is often all it takes."),
            ]
        )
    }

    /// ```
    /// 2 . 3 . 2
    /// 1 . | . 1
    /// . . 1 . .
    /// ```
    static let deepWaterBoard = HashiPuzzle.build(
        rows: 3, cols: 5,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),   // 0 A
            (GridPosition(row: 0, col: 2), 3),   // 1 B
            (GridPosition(row: 0, col: 4), 2),   // 2 C
            (GridPosition(row: 1, col: 0), 1),   // 3 D
            (GridPosition(row: 1, col: 4), 1),   // 4 E
            (GridPosition(row: 2, col: 2), 1),   // 5 F
        ],
        bridgeNetwork: [
            PairKey(0, 1): 1, PairKey(1, 2): 1,
            PairKey(0, 3): 1, PairKey(2, 4): 1,
            PairKey(1, 5): 1, PairKey(3, 4): 0,
        ]
    )

    private static func deepWaterLesson() -> TutorialLesson {
        let p = deepWaterBoard
        return TutorialLesson(
            id: "deepContradiction", technique: .deepContradiction,
            title: "Deep Water",
            summary: "Chase the what-if further down.",
            puzzle: p,
            steps: [
                .sayHighlighting("Look at the long middle corridor. Suppose it held a bridge — nothing breaks immediately. Chase it.",
                                 islands: [3, 4], edges: [edge(p, 3, 4)]),
                .sayHighlighting("A bridge there would cross the corridor down to this 1 — the only corridor that lonely island has. Two steps in, the board breaks: that 1 could never be reached.",
                                 islands: [5], edges: [edge(p, 1, 5)]),
                .requireBridge("So the middle stays empty, and the 1's lifeline is certain. Draw it.",
                               edge: edge(p, 1, 5), count: 1),
                .solveFreely("The rest follows. Finish the board."),
                .celebrate("Deep Water: when one step doesn't break the board, follow the forced moves further. The hardest puzzles live down here."),
            ]
        )
    }
}
