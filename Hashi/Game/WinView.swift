import SwiftUI

/// The win card: time in big rounded numerals, the vermillion hanko seal
/// stamping down, streak state for dailies, and the technique recap —
/// the win screen teaches.
struct WinView: View {
    let game: HashiGame
    let isNewBest: Bool
    /// Set when this board was a taste of something the player doesn't own —
    /// the weekend Daily hands free players a large board.
    var onUnlock: (() -> Void)?
    @Environment(ProgressStore.self) private var progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var stamped = false

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 6) {
                        Text(game.dailyKey != nil ? "Daily solved" : "Solved")
                            .font(Theme.heading)
                            .foregroundStyle(Theme.ink)
                        Text(TimeFormatting.clock(game.elapsed))
                            .font(Theme.numberFont(size: 40))
                            .foregroundStyle(Theme.bridge)
                        if isNewBest {
                            Text("New best time")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.foam)
                        }
                        if let day = game.dailyKey {
                            streakLine(day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    seal
                        .offset(x: -8, y: -6)
                }
                .padding(.top, 26)

                recap

                if let onUnlock {
                    VStack(spacing: 8) {
                        Text("That was a large board, free because it is this week's Daily. Large boards are part of the full game.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                        Button("See what's included", action: onUnlock)
                            .font(.subheadline.weight(.semibold))
                            .tint(Theme.bridge)
                    }
                    .padding(.horizontal, 24)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.island)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bridge))
                }
                .buttonStyle(.hashi)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            if reduceMotion {
                stamped = true
            } else {
                withAnimation(Motion.stamp.delay(0.25)) { stamped = true }
            }
        }
    }

    /// The hanko: a vermillion seal reading 橋 (hashi — bridge).
    private var seal: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.vermillion)
            Text("橋")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.island)
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(stamped ? -8 : -8))
        .scaleEffect(stamped ? 1 : 2.2)
        .opacity(stamped ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func streakLine(_ day: DayKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Theme.vermillion)
            Text("\(progress.daily.currentStreak) day streak")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            if progress.daily.currentStreak == progress.daily.bestStreak
                && progress.daily.bestStreak > 1 {
                Text("· best")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.top, 2)
    }

    /// What this puzzle exercised — each row a door back into the lesson.
    @ViewBuilder
    private var recap: some View {
        let used = game.generated.techniqueProfile
            .filter { $0.value > 0 }
            .keys.sorted()
        if !used.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("This puzzle used")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                ForEach(used) { technique in
                    HStack {
                        Circle()
                            .fill(Theme.bridge)
                            .frame(width: 6, height: 6)
                        Text(technique.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("×\(game.generated.techniqueProfile[technique] ?? 0)")
                            .font(Theme.numberFont(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sea))
            .padding(.horizontal, 24)
        }
    }
}
