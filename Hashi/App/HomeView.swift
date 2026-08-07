import SwiftUI

struct HomeView: View {
    @Binding var path: [Route]
    @Environment(ProgressStore.self) private var progress
    @Environment(PuzzleCache.self) private var cache
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    @State private var size: BoardSize = .small
    @State private var difficulty: Difficulty = .easy
    /// Restoring the pickers fires their gates; the flag keeps restoration
    /// from being mistaken for a player action.
    @State private var isRestoring = true

    private var today: DayKey { DayKey(date: .now) }

    var body: some View {
        ZStack {
            SeaBackground()
            // The content is short; on a large screen it centres rather than
            // clinging to the top, and still scrolls when Dynamic Type grows it
            // past the screen.
            ScrollView {
                VStack(spacing: 18) {
                    wordmark
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    DailyCard(today: today) {
                        path.append(.daily(today))
                    }

                    if progress.savedGame != nil {
                        continueCard
                    }

                    newGameCard

                    row("Learn", symbol: "book") { path.append(.learn) }
                    row("Practice", symbol: "repeat") { path.append(.practiceMenu) }
                    row("Stats", symbol: "chart.bar") { path.append(.stats) }
                    row("Settings", symbol: "gearshape") { path.append(.settings) }
                }
                .frame(maxWidth: Metrics.column)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            if isRestoring {
                if let last = progress.lastPlayed {
                    // Still respect the gate, quietly — no sheet. At launch
                    // `isUnlocked` already reflects the cached flag, which
                    // `EntitlementStore.init` reads synchronously before any
                    // await precisely so a paying customer whose last game was
                    // large is not shown a paywall on frame one. A player who
                    // no longer owns large simply keeps the default size.
                    if FeatureGate.isSizeAvailable(last.size, unlocked: entitlements.isUnlocked) {
                        size = last.size
                    }
                    difficulty = last.difficulty
                }
                isRestoring = false
            }
            cache.warm(.standard(size, difficulty))
        }
        .onChange(of: size) { previous, selected in
            guard !isRestoring else { return }
            // Snap back rather than hide the segment — a hidden feature can't
            // be sold. The warm must stay below this guard: building a large
            // board costs real CPU for a puzzle they can't open.
            guard FeatureGate.isSizeAvailable(selected, unlocked: entitlements.isUnlocked) else {
                size = previous
                paywall.present(.largeBoards)
                return
            }
            cache.warm(.standard(size, difficulty))
        }
        .onChange(of: difficulty) { warmIfSettled() }
    }

    private func warmIfSettled() {
        guard !isRestoring else { return }
        cache.warm(.standard(size, difficulty))
    }

    /// The lockup: "Just Hashi" with a bridge stroke through the wordmark —
    /// the game's signature drawn in its own ink.
    private var wordmark: some View {
        ViewThatFits {
            ForEach(Metrics.wordmark, id: \.self) { size in
                wordmarkLockup(size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Just Hashi")
        .accessibilityAddTraits(.isHeader)
    }

    private func wordmarkLockup(size: CGFloat) -> some View {
        VStack(spacing: size * 0.14) {
            Text("JUST")
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .kerning(size * 0.18)
                .foregroundStyle(Theme.inkSoft)
            Text("Hashi")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            // The signature drawn in the game's own language: two islands,
            // one double bridge.
            HStack(spacing: size * 0.1) {
                islandDot(size)
                VStack(spacing: size * 0.08) {
                    Capsule().fill(Theme.bridge).frame(height: size * 0.05)
                    Capsule().fill(Theme.bridge).frame(height: size * 0.05)
                }
                .frame(width: size * 1.1)
                islandDot(size)
            }
        }
    }

    private func islandDot(_ size: CGFloat) -> some View {
        Circle()
            .fill(Theme.island)
            .overlay(Circle().stroke(Theme.islandRim, lineWidth: max(1.5, size * 0.035)))
            .frame(width: size * 0.3, height: size * 0.3)
    }

    private var continueCard: some View {
        Button {
            path.append(.resumeGame)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if let saved = progress.savedGame {
                        Text(TimeFormatting.clock(saved.elapsed))
                            .font(Theme.numberFont(size: 14))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: Metrics.glyph, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        }
        .buttonStyle(.hashi)
    }

    private var newGameCard: some View {
        VStack(spacing: 14) {
            Picker("Size", selection: $size) {
                ForEach(BoardSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                path.append(.game(size: size, difficulty: difficulty))
            } label: {
                Text("Play")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.island)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bridge))
            }
            .buttonStyle(.hashi)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.bridge)
                    .frame(width: 26)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: Metrics.glyph, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        }
        .buttonStyle(.hashi)
    }
}

/// The daily puzzle card: date, size/difficulty, streak flame, done state.
struct DailyCard: View {
    let today: DayKey
    let onPlay: () -> Void
    @Environment(ProgressStore.self) private var progress

    private var spec: (size: BoardSize, difficulty: Difficulty) {
        DailySeed.spec(for: today)
    }

    var body: some View {
        Button(action: onPlay) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(spec.size.label) · \(spec.difficulty.label)")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if let time = progress.dailyTime(today) {
                    doneSeal(time)
                } else {
                    streakBadge
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.bridge.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.hashi)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var streakBadge: some View {
        let streak = progress.displayStreak(today: today)
        if streak > 0 {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Theme.vermillion)
                Text("\(streak)")
                    .font(Theme.numberFont(size: 17))
                    .foregroundStyle(Theme.ink)
            }
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: Metrics.glyph, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func doneSeal(_ time: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Text(TimeFormatting.clock(time))
                .font(Theme.numberFont(size: 15))
                .foregroundStyle(Theme.inkSoft)
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.vermillion)
                Text("橋")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.island)
            }
            .frame(width: 28, height: 28)
            .rotationEffect(.degrees(-8))
        }
    }

    private var accessibilityText: String {
        if let time = progress.dailyTime(today) {
            return "Daily puzzle, completed in \(TimeFormatting.clock(time))"
        }
        let streak = progress.displayStreak(today: today)
        return streak > 0
            ? "Daily puzzle, \(spec.size.label) \(spec.difficulty.label), \(streak) day streak"
            : "Daily puzzle, \(spec.size.label) \(spec.difficulty.label)"
    }
}
