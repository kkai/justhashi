import Foundation
import Observation

/// All persisted progress: settings, best times, stats, mastery, the daily
/// streak, and the in-progress game. UserDefaults + Codable, versioned keys.
@Observable @MainActor
final class ProgressStore {
    private let defaults: UserDefaults

    private enum Key {
        static let bestTimes = "hashi.bestTimes.v1"
        static let saveGame = "hashi.saveGame.v1"
        static let stats = "hashi.stats.v1"
        static let mastery = "hashi.mastery.v1"
        static let settings = "hashi.settings.v1"
        static let lastPlayed = "hashi.lastPlayed.v1"
        static let daily = "hashi.daily.v1"
    }

    /// The size/difficulty the player last started a game with, so the pickers
    /// come back where they left them and the cache can warm the right key.
    struct GameChoice: Codable, Hashable {
        let size: BoardSize
        let difficulty: Difficulty
    }

    struct Settings: Codable, Equatable {
        var hapticsEnabled = true
        var showErrors = true
        /// Auto-complete islands the first two techniques force. Off by
        /// default — drawing bridges is the game.
        var autoCompleteForced = false
        /// Show remaining capacity instead of the clue (expert mode).
        var showRemainingCount = false
    }

    struct Stats: Codable, Equatable {
        var puzzlesSolved = 0
        var totalPlayTime: TimeInterval = 0
        var solvedBySize: [BoardSize: Int] = [:]
        var solvedByDifficulty: [Difficulty: Int] = [:]
    }

    struct BestTimeKey: Hashable, Codable {
        let size: BoardSize
        let difficulty: Difficulty
    }

    /// The daily-puzzle record. `completedTimes` is keyed by `DayKey.isoString`
    /// so the JSON stays readable and time-zone-free.
    struct DailyRecord: Codable, Equatable {
        var lastCompleted: DayKey?
        var currentStreak = 0
        var bestStreak = 0
        var completedTimes: [String: TimeInterval] = [:]
    }

    private(set) var bestTimes: [BestTimeKey: TimeInterval] = [:]
    private(set) var stats = Stats()
    /// Mirrors the persisted save. Held as observable state rather than re-read
    /// on demand so the Continue card appears the moment a game is saved —
    /// reading UserDefaults inside a view body never invalidates it.
    private(set) var savedGame: HashiGame.Snapshot?
    private(set) var lastPlayed: GameChoice?
    private(set) var daily = DailyRecord()
    var settings = Settings() {
        didSet { save(settings, key: Key.settings) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        bestTimes = load([BestTimeKey: TimeInterval].self, key: Key.bestTimes) ?? [:]
        stats = load(Stats.self, key: Key.stats) ?? Stats()
        settings = load(Settings.self, key: Key.settings) ?? Settings()
        savedGame = load(HashiGame.Snapshot.self, key: Key.saveGame)
        lastPlayed = load(GameChoice.self, key: Key.lastPlayed)
        daily = load(DailyRecord.self, key: Key.daily) ?? DailyRecord()
    }

    /// Records the *requested* size/difficulty for a new game.
    func recordLastPlayed(size: BoardSize, difficulty: Difficulty) {
        let choice = GameChoice(size: size, difficulty: difficulty)
        guard choice != lastPlayed else { return }
        lastPlayed = choice
        save(choice, key: Key.lastPlayed)
    }

    // MARK: - Best times / stats

    func bestTime(size: BoardSize, difficulty: Difficulty) -> TimeInterval? {
        bestTimes[BestTimeKey(size: size, difficulty: difficulty)]
    }

    /// Records a solve; returns true when it's a new best time.
    @discardableResult
    func recordSolve(size: BoardSize, difficulty: Difficulty, time: TimeInterval) -> Bool {
        stats.puzzlesSolved += 1
        stats.totalPlayTime += time
        stats.solvedBySize[size, default: 0] += 1
        stats.solvedByDifficulty[difficulty, default: 0] += 1
        save(stats, key: Key.stats)

        let key = BestTimeKey(size: size, difficulty: difficulty)
        let isRecord = bestTimes[key].map { time < $0 } ?? true
        if isRecord {
            bestTimes[key] = time
            save(bestTimes, key: Key.bestTimes)
        }
        return isRecord
    }

    // MARK: - Daily streak

    func hasCompletedDaily(_ day: DayKey) -> Bool {
        daily.completedTimes[day.isoString] != nil
    }

    func dailyTime(_ day: DayKey) -> TimeInterval? {
        daily.completedTimes[day.isoString]
    }

    /// Whether today's streak is at risk (streak alive, today not yet done).
    /// Computed, never stored — storage would go stale at midnight.
    func streakIsAtRisk(today: DayKey) -> Bool {
        daily.currentStreak > 0
            && daily.lastCompleted == today.previous()
            && !hasCompletedDaily(today)
    }

    /// The streak to *show*: 0 when the chain is already broken (yesterday
    /// missed), even before today is played.
    func displayStreak(today: DayKey) -> Int {
        guard let last = daily.lastCompleted else { return 0 }
        if last == today || last == today.previous() { return daily.currentStreak }
        return 0
    }

    /// Records a completed daily. Idempotent per day; increments on
    /// consecutive days, resets to 1 otherwise.
    func recordDailyCompleted(day: DayKey, time: TimeInterval) {
        guard !hasCompletedDaily(day) else { return }
        daily.completedTimes[day.isoString] = time
        if daily.lastCompleted == day.previous() {
            daily.currentStreak += 1
        } else {
            daily.currentStreak = 1
        }
        // Only move forward — replaying an older day must not rewind the chain.
        if daily.lastCompleted == nil || daily.lastCompleted! < day {
            daily.lastCompleted = day
        }
        daily.bestStreak = max(daily.bestStreak, daily.currentStreak)
        save(daily, key: Key.daily)
    }

    // MARK: - Save game

    func saveGame(_ snapshot: HashiGame.Snapshot) {
        savedGame = snapshot
        save(snapshot, key: Key.saveGame)
    }

    func loadSavedGame() -> HashiGame.Snapshot? {
        savedGame
    }

    func clearSavedGame() {
        savedGame = nil
        defaults.removeObject(forKey: Key.saveGame)
    }

    // MARK: - Mastery (used by MasteryTracker)

    func loadMastery<T: Decodable>(_ type: T.Type) -> T? {
        load(type, key: Key.mastery)
    }

    func saveMastery(_ value: some Encodable) {
        save(value, key: Key.mastery)
    }

    // MARK: - Codable plumbing

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
