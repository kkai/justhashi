import SwiftUI

/// What a solved Daily shares: a line of text and a card image. Neither gives
/// anything away. The card draws the islands as bare dots with no clues and no
/// bridges, so a friend who hasn't played today's board learns nothing from it.
nonisolated enum DailyShare {
    static let siteURL = "kaikunze.de/justhashi/"

    /// `streak` is nil when the solve didn't extend the chain (an older daily
    /// finished late): the card then leaves the streak out rather than claim
    /// the current one.
    static func text(day: DayKey, rows: Int, cols: Int, time: TimeInterval, streak: Int?) -> String {
        var second = "\(rows)×\(cols) in \(TimeFormatting.clock(time))"
        if let streak, streak > 1 { second += " · \(streak) day streak" }
        return "Just Hashi daily, \(dateLabel(day))\n\(second)\n\(siteURL)"
    }

    /// "20 Oct 2026", fixed to English and the Gregorian calendar so the text
    /// reads the same wherever it is pasted.
    static func dateLabel(_ day: DayKey) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = (1...12).contains(day.month) ? months[day.month - 1] : "?"
        return "\(day.day) \(month) \(day.year)"
    }
}

/// The share image: the sea, the island silhouette, the time and the seal.
/// Rendered off screen by `ImageRenderer`, so it takes fixed sizes, not
/// Dynamic Type.
struct DailyShareCard: View {
    let puzzle: HashiPuzzle
    let day: DayKey
    let time: TimeInterval
    let streak: Int?

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Just Hashi")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(DailyShare.dateLabel(day))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
            silhouette
                .frame(width: 300, height: 300)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeFormatting.clock(time))
                        .font(Theme.numberFont(size: 40))
                        .foregroundStyle(Theme.bridge)
                    if let streak, streak > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Theme.vermillion)
                            Text("\(streak) day streak")
                                .foregroundStyle(Theme.ink)
                        }
                        .font(.system(size: 16, weight: .medium))
                    }
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Theme.vermillion)
                    Text("橋")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.island)
                }
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-8))
            }
            Text(DailyShare.siteURL)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(28)
        .frame(width: 380)
        .background(Theme.surface)
    }

    private var silhouette: some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(puzzle.cols), size.height / CGFloat(puzzle.rows))
            let origin = CGPoint(x: (size.width - cell * CGFloat(puzzle.cols)) / 2,
                                 y: (size.height - cell * CGFloat(puzzle.rows)) / 2)
            let sea = CGRect(origin: origin, size: CGSize(width: cell * CGFloat(puzzle.cols),
                                                         height: cell * CGFloat(puzzle.rows)))
            context.fill(Path(roundedRect: sea, cornerRadius: 14), with: .color(Theme.sea))
            let radius = cell * 0.3
            for island in puzzle.islands {
                let center = CGPoint(x: origin.x + (CGFloat(island.position.col) + 0.5) * cell,
                                     y: origin.y + (CGFloat(island.position.row) + 0.5) * cell)
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(Theme.island))
                context.stroke(dot, with: .color(Theme.islandRim), lineWidth: 1.5)
            }
        }
    }
}
