import Foundation
import Testing
@testable import Hashi

/// The cache's whole point is that a key can never generate twice
/// concurrently. The `init(generate:)` seam makes that provable in
/// milliseconds. (Kakuro's double-generation bug shipped precisely because no
/// test existed here.)
private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func bump(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        counts[key, default: 0] += 1
        return counts[key]!
    }

    func count(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }
}

@Suite("Puzzle cache")
@MainActor
struct PuzzleCacheTests {

    private static func instrumentedCache(_ counter: Counter, id: String,
                                          delayNanos: UInt64 = 0) -> PuzzleCache {
        PuzzleCache(generate: { options, _ in
            _ = counter.bump(id)
            if delayNanos > 0 {
                // Busy-wait so cancellation semantics stay deterministic.
                let start = DispatchTime.now().uptimeNanoseconds
                while DispatchTime.now().uptimeNanoseconds - start < delayNanos {}
            }
            return HashiGenerator.generate(
                .init(size: .small, difficulty: .easy, seed: options.seed))
        })
    }

    @Test func requestAfterWarmAwaitsTheSameGeneration() async {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id)
        cache.warm(.standard(.small, .easy))
        let request = cache.request(.standard(.small, .easy))
        let puzzle = await request.puzzle()
        #expect(puzzle != nil)
        #expect(counter.count(id) == 1, "warm + request must share one generation")
    }

    /// Two keys must never share one generation — a claim on `.small/.easy`
    /// cannot be served by the board built for `.small/.medium`.
    ///
    /// The bound is `>=`, not `==`, and that is not slack: settling a claim
    /// speculatively re-warms its key (`settledEntryRewarmsTheKey` pins that),
    /// so by the time both awaits return, a third generation is legitimately
    /// under way and whether its counter bump has landed is a race. An exact
    /// count here passed only by luck until enough suites were added to shift
    /// the scheduling.
    @Test func distinctKeysGenerateSeparately() async {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id)
        let a = cache.request(.standard(.small, .easy))
        let b = cache.request(.standard(.small, .medium))
        let first = await a.puzzle()
        let second = await b.puzzle()
        #expect(first != nil)
        #expect(second != nil)
        #expect(counter.count(id) >= 2, "one key was served by the other's generation")
    }

    @Test func settledEntryRewarmsTheKey() async {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id)
        let request = cache.request(.standard(.small, .easy))
        _ = await request.puzzle()
        // After the claim settles, the same key is speculatively re-warmed.
        #expect(cache.isWarm(.standard(.small, .easy)))
    }

    @Test func warmingANewKeyCancelsTheUnclaimedOld() {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id)
        cache.warm(.standard(.small, .easy))
        cache.warm(.standard(.medium, .hard))
        #expect(!cache.isWarm(.standard(.small, .easy)))
        #expect(cache.isWarm(.standard(.medium, .hard)))
    }

    @Test func dailyKeyIsCacheable() async {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id)
        let day = DayKey(year: 2026, month: 8, day: 7)
        cache.warm(.daily(day))
        let request = cache.request(.daily(day))
        let puzzle = await request.puzzle()
        #expect(puzzle != nil)
        #expect(counter.count(id) == 1)
    }

    @Test func dailyKeyOptionsAreDeterministic() {
        let day = DayKey(year: 2026, month: 8, day: 7)
        let a = PuzzleCache.CacheKey.daily(day).options
        let b = PuzzleCache.CacheKey.daily(day).options
        #expect(a.seed == b.seed)
        #expect(a.size == b.size)
        #expect(a.difficulty == b.difficulty)
    }

    /// A cancelled entry must be removed from the table — it resolves to nil
    /// forever, so leaving it would hang every later request for that key.
    @Test func cancellingDropsTheEntrySoALaterRequestStartsFresh() async {
        let counter = Counter()
        let id = UUID().uuidString
        let cache = Self.instrumentedCache(counter, id: id, delayNanos: 50_000_000)
        let request = cache.request(.standard(.small, .easy))
        let consumer = Task { await request.puzzle() }
        consumer.cancel()
        let cancelled = await consumer.value
        // Whether cancellation won the race or not, the follow-up request must
        // produce a real puzzle rather than hanging.
        let retry = cache.request(.standard(.small, .easy))
        let puzzle = await retry.puzzle()
        #expect(puzzle != nil)
        if cancelled == nil {
            #expect(counter.count(id) >= 1)
        }
    }
}
