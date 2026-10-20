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
    @State private var shareImage: Image?

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
                            .numberFont(40, relativeTo: .largeTitle)
                            .foregroundStyle(Theme.bridge)
                        if isNewBest {
                            Text("New best time")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.foam)
                        }
                        if let day = game.dailyKey {
                            streakLine(day)
                            shareButton(day)
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
                        .foregroundStyle(Theme.onBridge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bridge))
                }
                .buttonStyle(.hashi)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .task {
            guard let day = game.dailyKey else { return }
            let card = DailyShareCard(puzzle: game.puzzle, day: day,
                                      time: game.elapsed, streak: sharedStreak(day))
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            if let image = renderer.uiImage {
                shareImage = Image(uiImage: image)
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

    /// The streak this solve belongs to, or nil for an older daily finished
    /// late, which records a time but doesn't extend the chain.
    private func sharedStreak(_ day: DayKey) -> Int? {
        progress.daily.lastCompleted == day ? progress.daily.currentStreak : nil
    }

    @ViewBuilder
    private func shareButton(_ day: DayKey) -> some View {
        let text = DailyShare.text(day: day, rows: game.puzzle.rows, cols: game.puzzle.cols,
                                   time: game.elapsed, streak: sharedStreak(day))
        Group {
            if let shareImage {
                ShareLink(item: shareImage, subject: Text("Just Hashi daily"), message: Text(text),
                          preview: SharePreview("Just Hashi daily", image: shareImage)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .tint(Theme.bridge)
        .padding(.top, 4)
        .accessibilityLabel("Share result")
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
                            .numberFont(13)
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
