import Foundation
import Testing
@testable import Hashi

/// `TutorialPuzzles.bakedTechniques` is the source of truth for which lessons
/// exist; these tests iterate it so the list, the boards, and the scripts
/// cannot drift from the engine. (Kakuro shipped a No-Repeats lesson whose
/// board never needed No Repeats — this suite is why that can't recur.)
@Suite("Tutorial fixtures")
@MainActor
struct TutorialFixtureTests {

    @Test func everyTechniqueHasABakedLesson() {
        #expect(TutorialPuzzles.bakedTechniques.count == Technique.allCases.count + 1)
        for technique in Technique.allCases {
            #expect(TutorialPuzzles.bakedTechniques.contains(technique))
        }
        #expect(TutorialPuzzles.bakedTechniques.contains(nil))   // the rules lesson
    }

    @Test func bakedBoardsAreUniqueAndTeachable() {
        for technique in TutorialPuzzles.bakedTechniques {
            let lesson = TutorialPuzzles.lesson(for: technique)
            let unique = BacktrackingSolver.countSolutions(lesson.puzzle, limit: 4)
            #expect(unique.count == 1 && !unique.aborted,
                    "\(lesson.id): board must have exactly one solution, found \(unique.count)")
            let logical = LogicalSolver.solve(lesson.puzzle)
            #expect(logical.solved, "\(lesson.id): board must be solvable inside the curriculum")
        }
    }

    /// Every scripted `requireBridge` must match the board's unique solution —
    /// a script step asking for a wrong bridge would strand the lesson.
    @Test func scriptStepsAreLegal() {
        for technique in TutorialPuzzles.bakedTechniques {
            let lesson = TutorialPuzzles.lesson(for: technique)
            for step in lesson.steps {
                if case let .requireBridge(_, edge, count) = step {
                    #expect(edge >= 0 && edge < lesson.puzzle.edges.count,
                            "\(lesson.id): edge id out of range")
                    #expect(lesson.puzzle.solution[edge] >= count,
                            "\(lesson.id): script asks for \(count) on edge \(edge), solution has \(lesson.puzzle.solution[edge])")
                }
                if case let .sayHighlighting(_, islands, edges) = step {
                    for island in islands {
                        #expect(island < lesson.puzzle.islands.count)
                    }
                    for edge in edges {
                        #expect(edge < lesson.puzzle.edges.count)
                    }
                }
            }
            // Each lesson ends with a celebration.
            if case .celebrate = lesson.steps.last {} else {
                Issue.record("\(lesson.id): last step must be celebrate")
            }
        }
    }

    /// Walks every baked lesson through the TutorialEngine exactly as a player
    /// would: Next through the talk, draw required bridges, solve the exam
    /// with the logical solver. Every lesson must reach `finished`.
    @Test func tutorialEngineWalksEveryBakedLesson() {
        for technique in TutorialPuzzles.bakedTechniques {
            let lesson = TutorialPuzzles.lesson(for: technique)
            let engine = TutorialEngine(lesson: lesson)
            var guardCounter = 0
            while !engine.finished, guardCounter < 300 {
                guardCounter += 1
                switch engine.currentStep {
                case .say, .sayHighlighting, .celebrate:
                    engine.next()
                case let .requireBridge(_, edge, count):
                    // Cycle until the corridor holds the required count.
                    let before = engine.game.board.bridges[edge]
                    engine.handleCycleEdge(edge)
                    let after = engine.game.board.bridges[edge]
                    #expect(after != before, "\(lesson.id): cycle had no effect")
                    _ = count
                case .solveFreely:
                    // Play the solver's next forced bridge.
                    guard let step = LogicalSolver.nextStep(puzzle: engine.game.puzzle,
                                                            board: engine.game.board) else {
                        Issue.record("\(lesson.id): exam stalled — no next step")
                        return
                    }
                    var acted = false
                    for change in step.boundChanges
                    where Int(change.newMin) > engine.game.board.bridges[change.edge] {
                        while engine.game.board.bridges[change.edge] < Int(change.newMin) {
                            engine.handleCycleEdge(change.edge)
                            acted = true
                        }
                    }
                    #expect(acted, "\(lesson.id): solver step placed nothing")
                case nil:
                    Issue.record("\(lesson.id): ran out of steps without finishing")
                    return
                }
            }
            #expect(engine.finished, "\(lesson.id): did not finish within bounds")
            #expect(engine.game.phase == .won || !lessonHasExam(lesson),
                    "\(lesson.id): exam should end in a solved board")
        }
    }

    private func lessonHasExam(_ lesson: TutorialLesson) -> Bool {
        lesson.steps.contains { if case .solveFreely = $0 { true } else { false } }
    }

    /// Off-script input is rejected and does not mutate the board.
    @Test func offScriptInputIsRejected() {
        let lesson = TutorialPuzzles.lesson(for: .fullIsland)
        let engine = TutorialEngine(lesson: lesson)
        // First step is sayHighlighting: any board interaction is off-script.
        let before = engine.game.board
        engine.handleCycleEdge(0)
        #expect(engine.game.board == before)
        #expect(engine.stepIndex == 0)
    }

    /// Lessons load fast enough to never need a spinner (they're baked, and
    /// solving these boards is microseconds — this is the loose backstop).
    @Test func bakedLessonsLoadPromptly() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for technique in TutorialPuzzles.bakedTechniques {
                _ = TutorialEngine(lesson: TutorialPuzzles.lesson(for: technique))
            }
        }
        #expect(elapsed < .seconds(1))
    }
}

@Suite("Practice drills")
@MainActor
struct PracticeDrillTests {
    /// Searchable drills must actually exercise their technique.
    @Test func searchableDrillsContainTheirTechnique() {
        let searchable = Technique.allCases.filter { !PracticeDrills.handAuthored.contains($0) }
        for technique in searchable {
            let drill = PracticeDrills.drillPuzzle(for: technique, seed: 42)
            #expect(drill.techniqueProfile[technique, default: 0] >= 1,
                    "\(technique) drill (seed 42) has zero uses of its technique")
        }
    }

    /// Pins the premise behind `handAuthored`: these techniques never appear
    /// in generated traces, so their drills must be baked. If this fails,
    /// detector precedence changed — revisit the list.
    @Test func handAuthoredTechniquesAreUnsearchable() {
        var histogram: [Technique: Int] = [:]
        for seed in stride(from: UInt64(2000), to: 2012, by: 1) {
            let g = HashiGenerator.generate(.init(size: .small, difficulty: .hard, seed: seed))
            for (technique, count) in g.techniqueProfile {
                histogram[technique, default: 0] += count
            }
        }
        #expect(histogram[.segmentLink, default: 0] == 0)
        #expect(histogram[.deepContradiction, default: 0] == 0)
    }

    @Test func handAuthoredDrillsAreVerified() {
        for technique in PracticeDrills.handAuthored {
            let drill = PracticeDrills.drillPuzzle(for: technique, seed: 1)
            let unique = BacktrackingSolver.countSolutions(drill.puzzle, limit: 2)
            #expect(unique.count == 1 && !unique.aborted)
            #expect(LogicalSolver.solve(drill.puzzle).solved)
        }
    }
}
