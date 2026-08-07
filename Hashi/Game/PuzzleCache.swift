import Foundation
import Observation

/// Pre-generates the next puzzle per key off the main actor so starting a game
/// rarely blocks on generation.
///
/// The table holds **tasks, not finished puzzles**. That is the whole design:
/// a request for a key that is already generating simply awaits that task, so
/// the failure mode this replaced in Kakuro — a cache miss starting a *second*
/// generation while the first was still running, and the player waiting on the
/// later one — cannot be expressed. There is one table, so there is nothing to
/// keep in sync.
@Observable @MainActor
final class PuzzleCache {

    enum CacheKey: Hashable {
        case standard(BoardSize, Difficulty)
        case daily(DayKey)

        var options: HashiGenerator.Options {
            switch self {
            case let .standard(size, difficulty):
                HashiGenerator.Options(size: size, difficulty: difficulty)
            case let .daily(day):
                HashiGenerator.Options(size: DailySeed.spec(for: day).size,
                                       difficulty: DailySeed.spec(for: day).difficulty,
                                       seed: DailySeed.seed(for: day))
            }
        }
    }

    /// A `final class` because identity matters: a late-finishing task must not
    /// clobber a fresher entry for the same key.
    private final class Entry {
        let task: Task<GeneratedHashiPuzzle?, Never>
        let progress: AsyncStream<Double>
        var isClaimed = false

        init(task: Task<GeneratedHashiPuzzle?, Never>, progress: AsyncStream<Double>) {
            self.task = task
            self.progress = progress
        }
    }

    /// Not view state — nothing reads the table in a body, and marking it
    /// observed would invalidate views on every prefetch.
    @ObservationIgnored private var entries: [CacheKey: Entry] = [:]
    @ObservationIgnored private let generate:
        @Sendable (HashiGenerator.Options, HashiGenerator.Control) -> GeneratedHashiPuzzle

    /// The `generate` seam mirrors `ProgressStore(userDefaults:)` — it makes
    /// the "did we generate once or twice?" question testable in milliseconds.
    init(generate: @escaping @Sendable (HashiGenerator.Options, HashiGenerator.Control)
         -> GeneratedHashiPuzzle = { HashiGenerator.generate($0, control: $1) }) {
        self.generate = generate
    }

    // MARK: - API

    /// Keeps a warm entry for this key, cancelling any other *running,
    /// unclaimed* generation. At most one speculative generation runs at a
    /// time — several concurrent ones would starve the cooperative pool and
    /// make the board the player is actually waiting for slower.
    func warm(_ key: CacheKey) {
        for (other, entry) in entries where other != key && !entry.isClaimed {
            entry.task.cancel()
            entries.removeValue(forKey: other)
        }
        guard entries[key] == nil else { return }
        entries[key] = makeEntry(key, priority: .utility)
    }

    /// Claims this key, starting a generation only if none is running.
    func request(_ key: CacheKey) -> PuzzleRequest {
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
        } else {
            entry = makeEntry(key, priority: .userInitiated)
            entries[key] = entry
        }
        entry.isClaimed = true
        return PuzzleRequest(task: entry.task, progress: entry.progress) { [weak self] cancelled in
            self?.settle(key, entry: entry, cancelled: cancelled)
        }
    }

    /// Whether a generation for this key is running or already finished.
    /// Exists so tests can assert cache state directly.
    func isWarm(_ key: CacheKey) -> Bool {
        entries[key] != nil
    }

    // MARK: - Internals

    private func makeEntry(_ key: CacheKey, priority: TaskPriority) -> Entry {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let options = key.options
        let generate = self.generate
        // Detached, so `Task.isCancelled` inside refers to the same task the
        // consumer cancels — no nesting, no second cancellation hop.
        let task = Task.detached(priority: priority) { () -> GeneratedHashiPuzzle? in
            let control = HashiGenerator.Control(
                isCancelled: { Task.isCancelled },
                onProgress: { continuation.yield($0) })
            let puzzle = generate(options, control)
            continuation.finish()
            return Task.isCancelled ? nil : puzzle
        }
        return Entry(task: task, progress: stream)
    }

    /// Retires a claimed entry once its consumer has the value.
    ///
    /// Identity-guarded: a task that finishes late must not remove an entry
    /// created after it.
    ///
    /// Dropping a **cancelled** entry is correctness, not tidiness — a
    /// cancelled task resolves to `nil` forever, so leaving it in the table
    /// would make every later request for that key hang on a value that never
    /// comes. Cancelled entries are dropped without re-warming; the player
    /// backed out, so speculatively rebuilding the board they abandoned is
    /// exactly the work we just cancelled.
    private func settle(_ key: CacheKey, entry: Entry, cancelled: Bool) {
        guard entries[key] === entry else { return }
        entries.removeValue(forKey: key)
        guard !cancelled else { return }
        warm(key)
    }
}

/// A claim on a puzzle: its progress stream and a handle to await.
///
/// Both are handed over in one synchronous call. Splitting them would put a
/// suspension point between "start watching progress" and "await the puzzle",
/// where updates get missed or the entry is rebuilt underneath.
@MainActor
struct PuzzleRequest {
    private let task: Task<GeneratedHashiPuzzle?, Never>
    let progress: AsyncStream<Double>
    private let onSettled: @MainActor (Bool) -> Void

    fileprivate init(task: Task<GeneratedHashiPuzzle?, Never>,
                     progress: AsyncStream<Double>,
                     onSettled: @escaping @MainActor (Bool) -> Void) {
        self.task = task
        self.progress = progress
        self.onSettled = onSettled
    }

    /// The generated puzzle, or `nil` if the work was cancelled.
    ///
    /// This is where a caller's cancellation finally reaches the generator:
    /// the loader's `.task` is cancelled on pop → `onCancel` fires → the
    /// detached task is cancelled → `Control.isCancelled` returns true on the
    /// next probe.
    func puzzle() async -> GeneratedHashiPuzzle? {
        // Bind the Sendable Task locally: `onCancel` is @Sendable and may run
        // off-main, so it must not capture MainActor-isolated state.
        let handle = task
        let result = await withTaskCancellationHandler {
            await handle.value
        } onCancel: {
            handle.cancel()
        }
        onSettled(result == nil)
        return result
    }
}
