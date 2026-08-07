import SwiftUI

struct StatsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements

    private var today: DayKey { DayKey(date: .now) }

    var body: some View {
        ZStack {
            Theme.sea.ignoresSafeArea()
            ScrollView {
                // The panels are gated, not the screen. The daily streak
                // belongs to the free Daily, so locking everything would hide
                // data the player owns — and a free player who taps through to
                // their real streak plus one honest locked card is a better
                // sell than a sheet fired from the row they tapped.
                VStack(spacing: 16) {
                    dailySection
                    if entitlements.isUnlocked {
                        overview
                        bestTimes
                        masteryCard
                    } else {
                        LockedFeaturePanel(feature: .stats)
                    }
                }
                .frame(maxWidth: Metrics.column)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Stats")
        .navigationTitleDisplay(.large)
    }

    private var overview: some View {
        card("Overview") {
            statRow("Puzzles solved", value: "\(progress.stats.puzzlesSolved)")
            statRow("Time played", value: TimeFormatting.duration(progress.stats.totalPlayTime))
        }
    }

    private var dailySection: some View {
        card("Daily") {
            statRow("Current streak", value: "\(progress.displayStreak(today: today))")
            statRow("Best streak", value: "\(progress.daily.bestStreak)")
            statRow("Dailies completed", value: "\(progress.daily.completedTimes.count)")
        }
    }

    private var bestTimes: some View {
        card("Best times") {
            ForEach(BoardSize.allCases) { size in
                ForEach(Difficulty.allCases) { difficulty in
                    if let time = progress.bestTime(size: size, difficulty: difficulty) {
                        statRow("\(size.label) · \(difficulty.label)",
                                value: TimeFormatting.clock(time))
                    }
                }
            }
            if progress.bestTimes.isEmpty {
                Text("Solve a puzzle to set your first time.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// Where "mastery display is paid" is literally true. Everywhere else the
    /// mastery surfaces (Learn badges, Practice progress lines) simply follow
    /// their own row's gate.
    private var masteryCard: some View {
        card("Technique path") {
            ForEach(Technique.allCases) { technique in
                let record = mastery.record(for: technique)
                HStack {
                    Text(technique.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(masteryLabel(record))
                        .font(.footnote)
                        .foregroundStyle(record.state == .learned ? Theme.foam : Theme.inkSoft)
                }
            }
        }
    }

    private func masteryLabel(_ record: MasteryTracker.Record) -> String {
        switch record.state {
        case .locked: "Locked"
        case .learned: "Learned"
        default: "\(record.unaidedUses) of \(MasteryTracker.learnedThreshold)"
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(Theme.numberFont(size: 15))
                .foregroundStyle(Theme.bridge)
        }
    }
}
