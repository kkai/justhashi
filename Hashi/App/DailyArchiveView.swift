import SwiftUI

/// Which past days the archive offers. Kept apart from the view so the range
/// can be tested without a calendar UI.
nonisolated enum DailyArchive {
    /// The day Just Hashi 1.0 was submitted. Any day can be generated, but a
    /// daily from before the app existed was never anybody's daily.
    static let firstDay = DayKey(year: 2026, month: 8, day: 8)

    /// Newest first, today excluded (Home already carries it), at most a year.
    static func days(before today: DayKey, limit: Int = 366) -> [DayKey] {
        var days: [DayKey] = []
        var day = today.previous()
        while !(day < firstDay) && days.count < limit {
            days.append(day)
            day = day.previous()
        }
        return days
    }
}

/// Every past Daily, with the time for the ones already solved.
///
/// The list is visible to everyone, because the times in it are the player's
/// own. Opening a past board is part of the unlock, and a locked row stays
/// tappable and presents the paywall rather than doing nothing.
struct DailyArchiveView: View {
    @Binding var path: [Route]
    @Environment(ProgressStore.self) private var progress
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    private var days: [DayKey] { DailyArchive.days(before: DayKey(date: .now)) }

    var body: some View {
        ZStack {
            SeaBackground()
            ScrollView {
                LazyVStack(spacing: 10) {
                    if days.isEmpty {
                        Text("The first past Daily appears here tomorrow.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 40)
                    }
                    ForEach(days, id: \.self) { day in
                        row(day)
                    }
                }
                .frame(maxWidth: Metrics.column)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Past dailies")
        .navigationTitleDisplay(.large)
    }

    private var isOpen: Bool {
        FeatureGate.isAvailable(.dailyArchive, unlocked: entitlements.isUnlocked)
    }

    private func row(_ day: DayKey) -> some View {
        let spec = DailySeed.spec(for: day)
        let time = progress.dailyTime(day)
        return Button {
            if isOpen {
                path.append(.daily(day))
            } else {
                paywall.present(.dailyArchive)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text("\(spec.size.label) · \(spec.difficulty.label)")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if let time {
                    Text(TimeFormatting.clock(time))
                        .numberFont(15)
                        .foregroundStyle(Theme.inkSoft)
                }
                Image(systemName: isOpen ? "chevron.right" : "lock")
                    .font(.system(size: Metrics.glyph, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        }
        .buttonStyle(.hashi)
        .accessibilityLabel(accessibilityText(day, spec: spec, time: time))
        .accessibilityHint(isOpen ? "" : "Part of the full game")
    }

    private func accessibilityText(_ day: DayKey, spec: (size: BoardSize, difficulty: Difficulty),
                                   time: TimeInterval?) -> String {
        let date = day.date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        let base = "\(date), \(spec.size.label) \(spec.difficulty.label)"
        guard let time else { return base }
        return "\(base), completed in \(TimeFormatting.spoken(time))"
    }
}
