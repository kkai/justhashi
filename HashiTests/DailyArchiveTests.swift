import Foundation
import Testing
@testable import Hashi

@Suite("Daily archive")
struct DailyArchiveTests {

    @Test func newestFirstAndTodayExcluded() {
        let today = DayKey(year: 2026, month: 10, day: 20)
        let days = DailyArchive.days(before: today)
        #expect(days.first == DayKey(year: 2026, month: 10, day: 19))
        #expect(!days.contains(today))
        #expect(zip(days, days.dropFirst()).allSatisfy { $1 < $0 })
    }

    @Test func stopsAtLaunchDay() {
        let days = DailyArchive.days(before: DayKey(year: 2026, month: 8, day: 11))
        #expect(days == [DayKey(year: 2026, month: 8, day: 10),
                         DayKey(year: 2026, month: 8, day: 9),
                         DailyArchive.firstDay])
        #expect(DailyArchive.days(before: DailyArchive.firstDay).isEmpty)
    }

    @Test func capsAtAYear() {
        let days = DailyArchive.days(before: DayKey(year: 2030, month: 1, day: 1))
        #expect(days.count == 366)
    }

    /// Opening a past board is paid; today's stays free.
    @Test func pastDailiesNeedTheUnlock() {
        #expect(!FeatureGate.isAvailable(.dailyArchive, unlocked: false))
        #expect(FeatureGate.isAvailable(.dailyArchive, unlocked: true))
        #expect(FeatureGate.isDailyAvailable(DayKey(year: 2026, month: 10, day: 20), unlocked: false))
    }
}
