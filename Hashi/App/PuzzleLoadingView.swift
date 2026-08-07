import SwiftUI

/// Shown while the cache builds a board. Usually flashes past — generation is
/// milliseconds — but a cold large board deserves real progress, not a spinner.
struct PuzzleLoadingView: View {
    let fraction: Double
    let startedAt: Date
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.sea.ignoresSafeArea()
            VStack(spacing: 20) {
                TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                    // Only surface progress UI if loading is actually slow.
                    if context.date.timeIntervalSince(startedAt) > 0.4 {
                        VStack(spacing: 16) {
                            ProgressView(value: max(0.05, fraction))
                                .progressViewStyle(.linear)
                                .tint(Theme.bridge)
                                .frame(maxWidth: 220)
                            Text("Charting islands…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSoft)
                            Button("Cancel", action: onCancel)
                                .font(.subheadline)
                                .foregroundStyle(Theme.bridge)
                        }
                    }
                }
            }
        }
    }
}
