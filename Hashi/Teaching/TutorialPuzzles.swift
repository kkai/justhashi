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

            puzzle: p,
            steps: [
                .say("Hashi is played on islands. The number on an island says exactly how many bridges touch it, no more and no fewer."),
                .sayHighlighting("Bridges run along these corridors: straight lines, up-down or left-right, never diagonal.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .requireBridge("Drag from the 2 toward the 4 to draw your first bridge.",
                               edge: edge(p, 0, 1), count: 1),
                .requireBridge("A corridor can carry a second bridge. Drag the same way again to make it a double.",
                               edge: edge(p, 0, 1), count: 2),
                .say("That double finishes the 2, and its ring closes. The rings are worth watching: each one shows how much its island still needs."),
                .requireBridge("The 1 on the right needs a single bridge. Connect it to the 4.",
                               edge: edge(p, 1, 2), count: 1),
                .requireBridge("One more: link the 4 down to the last island.",
                               edge: edge(p, 1, 3), count: 1),
                .say("Two more rules and you know the game. Bridges may never cross each other, and the app will not draw one that would."),
                .celebrate("And every island has to end up in the same connected network, with no group left on its own. That is the whole game. Now to solve it properly."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("This 4 sits in a corner, so it has exactly two corridors, and 4 is two bridges in each. There is nothing to decide.",
                                 islands: [0], edges: [edge(p, 0, 1), edge(p, 0, 2)]),
                .requireBridge("Give the top corridor its double.", edge: edge(p, 0, 1), count: 2),
                .requireBridge("And the left corridor too.", edge: edge(p, 0, 2), count: 2),
                .say("A corner 4, an edge 6, a middle 8. Whenever the number equals two bridges to every neighbor, you can fill everything without working anything out."),
                .solveFreely("Every island here is full. Finish the board."),
                .celebrate("That is the fastest opening in Hashi. Scan for full islands first, every game."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("This 1 has a single neighbor. Wherever its bridge goes, there's only one place it can go.",
                                 islands: [0], edges: [edge(p, 0, 1)]),
                .requireBridge("Connect the 1 to its only neighbor.", edge: edge(p, 0, 1), count: 1),
                .sayHighlighting("Now look at the 3 you just touched: one bridge placed, and only one open corridor left. The remaining two bridges are forced.",
                                 islands: [1], edges: [edge(p, 1, 2)]),
                .requireBridge("Draw the double.", edge: edge(p, 1, 2), count: 2),
                .solveFreely("Finish the chain."),
                .celebrate("When an island has one road out, everything it needs goes down that road."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("This corner 3 could hold at most 4, a double each way. Three is one short of that, so each corridor carries at least one bridge. Only the question of where the double goes is still open.",
                                 islands: [0], edges: [edge(p, 0, 1), edge(p, 0, 3)]),
                .requireBridge("Place the guaranteed bridge toward the 2.", edge: edge(p, 0, 1), count: 1),
                .requireBridge("And the guaranteed bridge going down.", edge: edge(p, 0, 3), count: 1),
                .say("The same idea works for a 5 on an edge and a 7 in the middle: one short of full means at least one bridge in every direction."),
                .solveFreely("Use what you know to finish the board."),
                .celebrate("Knowing part of the answer still counts. Bank the guaranteed bridges early and the rest gets easier."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("The middle island needs 3. Its left neighbor is a 1, so that corridor can never carry more than one bridge.",
                                 islands: [1, 0], edges: [edge(p, 0, 1)]),
                .sayHighlighting("Count: 3 needed, at most 1 from the left. At least 2 must go right. The double is forced before you know anything else.",
                                 islands: [1, 2], edges: [edge(p, 1, 2)]),
                .requireBridge("Draw the forced double.", edge: edge(p, 1, 2), count: 2),
                .solveFreely("Finish the row."),
                .celebrate("Add up what the other corridors could carry. Whatever is missing belongs to the one that is left."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("Two 1s, side by side. A single bridge between them would satisfy both at once.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("But a finished island takes no more bridges, so those two would be sealed off with nothing joining them to the rest. Every island has to end up in one network, which makes that bridge wrong every time."),
                .requireBridge("Send the left 1 downward instead.", edge: edge(p, 0, 2), count: 1),
                .requireBridge("And the right 1 down too.", edge: edge(p, 1, 3), count: 1),
                .solveFreely("Connect what remains."),
                .celebrate("Before completing a small group, ask who gets left outside it. A 1 beside a 1, or a 2 beside a 2, is where this usually bites."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("Suppose the top pair were joined by a double, filling both 2s. The bottom islands could still pair up below, and the board would fall into two halves that never meet.",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("Whenever a group of joined islands is down to one corridor that reaches the outside, that corridor must carry a bridge. A group that spends its last exit on itself is stranded."),
                .requireBridge("Join the top islands with a single bridge, so each of them keeps a corridor free.",
                               edge: edge(p, 0, 1), count: 1),
                .requireBridge("Now spend the left 2's last bridge on its way out, down to the 1.",
                               edge: edge(p, 0, 2), count: 1),
                .solveFreely("Finish the board, keeping everyone connected."),
                .celebrate("Watch how many exits each group has left. When it is down to one, that corridor is not optional."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("Four 2s in a ring, and counting alone forces nothing. So suppose something instead. What if the top corridor held a double?",
                                 islands: [0, 1], edges: [edge(p, 0, 1)]),
                .say("Then both top 2s would be full and sealed off from the bottom pair, which breaks the board. So the supposition is wrong and the top corridor holds at most one bridge. Every corridor here works out the same way."),
                .requireBridge("Place a single on the top corridor.", edge: edge(p, 0, 1), count: 1),
                .solveFreely("Each corridor carries exactly one. Close the ring."),
                .celebrate("A supposition you can disprove is knowledge you get to keep, and one step of it is usually enough."),
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

            puzzle: p,
            steps: [
                .sayHighlighting("Look at the long middle corridor. Suppose it held a bridge. Nothing breaks straight away, so chase it further.",
                                 islands: [3, 4], edges: [edge(p, 3, 4)]),
                .sayHighlighting("A bridge there would cross the corridor running down to this 1, which is the only corridor that island has. Two steps in the board breaks, because nothing could ever reach that 1.",
                                 islands: [5], edges: [edge(p, 1, 5)]),
                .requireBridge("So the middle stays empty, and the 1's lifeline is certain. Draw it.",
                               edge: edge(p, 1, 5), count: 1),
                .solveFreely("The rest follows. Finish the board."),
                .celebrate("When one step does not break the board, follow the forced moves further out. This is where the hardest puzzles are won."),
            ]
        )
    }
}
