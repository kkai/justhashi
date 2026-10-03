import Foundation
import Testing
@testable import Hashi

/// What VoiceOver hears about the board (docs/ACCESSIBILITY.md).
@Suite("Board speech")
@MainActor
struct BoardSpeechTests {

    private func game(_ puzzle: HashiPuzzle) -> HashiGame {
        HashiGame(puzzle: GeneratedHashiPuzzle(puzzle: puzzle, difficulty: .easy, techniqueProfile: [:]))
    }

    @Test func actionsCycleTheBridgeAndSayWhatTheyDo() throws {
        let game = game(Fixtures.pair)
        let left = game.puzzle.islands[0], right = game.puzzle.islands[1]
        let edge = try #require(game.puzzle.edgesAt[left.id].first.map { game.puzzle.edges[$0] })
        #expect(BoardSpeech.actionName(edge: edge, from: left, game: game) == "Add a bridge to the 2 on the right")
        #expect(BoardSpeech.actionName(edge: edge, from: right, game: game) == "Add a bridge to the 2 on the left")

        var before = game.board.bridges[edge.id]
        game.cycleBridge(edge: edge.id)
        #expect(BoardSpeech.edgeChanged(edge, before: before, game: game)
                == "Single bridge between the 2 at row 1, column 1 and the 2 at row 1, column 3")
        #expect(BoardSpeech.actionName(edge: edge, from: left, game: game) == "Make the bridge to the 2 on the right double")

        before = game.board.bridges[edge.id]
        game.cycleBridge(edge: edge.id)
        let spoken = BoardSpeech.edgeChanged(edge, before: before, game: game)
        #expect(spoken.hasPrefix("Double bridge"))
        #expect(spoken.contains("The 2 is complete"))
        #expect(BoardSpeech.actionName(edge: edge, from: left, game: game) == "Remove the bridges to the 2 on the right")
    }

    @Test func unchangedMoveIsReported() throws {
        let game = game(Fixtures.pair)
        let edge = game.puzzle.edges[0]
        #expect(BoardSpeech.edgeChanged(edge, before: game.board.bridges[edge.id], game: game) == "Not allowed here")
    }

    @Test func sidesFollowTheGrid() {
        let a = Island(id: 0, position: GridPosition(row: 2, col: 2), clue: 1)
        #expect(BoardSpeech.side(of: Island(id: 1, position: GridPosition(row: 0, col: 2), clue: 1), from: a) == "above")
        #expect(BoardSpeech.side(of: Island(id: 1, position: GridPosition(row: 4, col: 2), clue: 1), from: a) == "below")
        #expect(BoardSpeech.side(of: Island(id: 1, position: GridPosition(row: 2, col: 0), clue: 1), from: a) == "on the left")
    }

    @Test func spokenTimeUsesWords() {
        #expect(TimeFormatting.spoken(247) == "4 minutes 7 seconds")
        #expect(TimeFormatting.spoken(60) == "1 minute")
    }
}
