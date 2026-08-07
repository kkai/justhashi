import Foundation

// CLI bench harness. Build: swiftc -O -o bench Hashi/Engine/*.swift bench/main.swift
// Commands: (none) smoke · calibrate · audit · time
// Output goes to stderr (stdout is block-buffered under a pipe).

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "smoke"

switch command {
case "smoke":
    let square = HashiPuzzle.build(
        rows: 3, cols: 3,
        islandSpecs: [
            (GridPosition(row: 0, col: 0), 2),
            (GridPosition(row: 0, col: 2), 2),
            (GridPosition(row: 2, col: 0), 2),
            (GridPosition(row: 2, col: 2), 2),
        ],
        bridgeNetwork: [
            PairKey(0, 1): 1, PairKey(0, 2): 1,
            PairKey(1, 3): 1, PairKey(2, 3): 1,
        ]
    )
    let result = BacktrackingSolver.countSolutions(square, limit: 4)
    log("square: solutions=\(result.count) aborted=\(result.aborted)")
    for size in BoardSize.allCases {
        for difficulty in Difficulty.allCases {
            let clock = ContinuousClock()
            var generated: GeneratedHashiPuzzle? = nil
            let elapsed = clock.measure {
                generated = HashiGenerator.generate(
                    .init(size: size, difficulty: difficulty, seed: 42))
            }
            let g = generated!
            let unique = BacktrackingSolver.countSolutions(g.puzzle, limit: 2)
            log("\(size.rawValue)/\(difficulty.rawValue): islands=\(g.puzzle.islands.count) " +
                "edges=\(g.puzzle.edges.count) band=\(g.difficulty.rawValue) " +
                "unique=\(unique.count == 1) t=\(elapsed)")
        }
    }

case "calibrate":
    // Score distribution per size over verified candidates → paste p33/p66
    // into DifficultyRater.thresholds.
    for size in BoardSize.allCases {
        var scores: [Int] = []
        var seed: UInt64 = 1000
        while scores.count < 60 {
            seed += 1
            let g = HashiGenerator.generate(.init(size: size, difficulty: .medium, seed: seed))
            let score = DifficultyRater.score(profile: g.techniqueProfile, solved: true)
            scores.append(score)
        }
        scores.sort()
        let p33 = scores[scores.count / 3]
        let p66 = scores[scores.count * 2 / 3]
        log("\(size.rawValue): n=\(scores.count) min=\(scores.first!) p33=\(p33) " +
            "p66=\(p66) max=\(scores.last!)")
    }

case "audit":
    // Shadowing audit: which techniques ever appear in solve traces?
    var histogram: [Technique: Int] = [:]
    var boards = 0
    for size in BoardSize.allCases {
        for difficulty in Difficulty.allCases {
            for offset in 0..<12 {
                let seed = UInt64(9000 + offset) &* 31 &+ UInt64(size.gridRows)
                let g = HashiGenerator.generate(.init(size: size, difficulty: difficulty, seed: seed))
                boards += 1
                for (technique, count) in g.techniqueProfile {
                    histogram[technique, default: 0] += count
                }
            }
        }
    }
    log("boards=\(boards)")
    for technique in Technique.allCases {
        log("\(technique): \(histogram[technique, default: 0])")
    }

case "time":
    for size in BoardSize.allCases {
        for difficulty in Difficulty.allCases {
            var times: [Duration] = []
            let clock = ContinuousClock()
            for offset in 0..<10 {
                let seed = UInt64(5000 + offset)
                let elapsed = clock.measure {
                    _ = HashiGenerator.generate(.init(size: size, difficulty: difficulty, seed: seed))
                }
                times.append(elapsed)
            }
            times.sort()
            log("\(size.rawValue)/\(difficulty.rawValue): p50=\(times[times.count / 2]) " +
                "max=\(times.last!)")
        }
    }

default:
    log("unknown command \(command)")
}
