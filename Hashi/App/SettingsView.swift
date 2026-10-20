import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        @Bindable var progress = progress
        Form {
            Section {
                Toggle("Haptics", isOn: $progress.settings.hapticsEnabled)
                Toggle("Show mistakes", isOn: $progress.settings.showErrors)
            } header: {
                Text("Play").foregroundStyle(Theme.ink)
            }
            Section {
                Toggle("Complete forced islands", isOn: $progress.settings.autoCompleteForced)
                Toggle("Show remaining count", isOn: $progress.settings.showRemainingCount)
            } footer: {
                Text("Complete forced islands draws bridges the first two techniques prove. Show remaining count replaces each island's number with how many bridges it still needs.")
                    .foregroundStyle(Theme.inkSoft)
            }
            storeSection
            siblingsSection
        }
        .navigationTitle("Settings")
        .navigationTitleDisplay(.inline)
        .onChange(of: progress.settings.hapticsEnabled) { _, enabled in
            Haptics.enabled = enabled
        }
        .task {
            // A failure raised on the paywall must not greet the player here.
            entitlements.clearTransientState()
        }
    }

    private var storeSection: some View {
        Section {
            if !entitlements.isUnlocked {
                Button("Unlock everything") {
                    paywall.present(.advancedLessons)
                }
            }
            // Apple requires a restore path for non-consumables, and it has to
            // be reachable even when the app already believes it is unlocked.
            // Unconditional on purpose.
            Button {
                Task { await entitlements.restore() }
            } label: {
                HStack {
                    Text("Restore purchases")
                    if entitlements.purchaseState == .restoring {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(entitlements.purchaseState.isBusy)
        } header: {
            Text("Just Hashi").foregroundStyle(Theme.ink)
        } footer: {
            // The system grey only nearly passed over this background.
            Text(storeFooter).foregroundStyle(Theme.inkSoft)
        }
    }

    /// The other Just Puzzles games that are on sale. Plain App Store links:
    /// no tracking, no prompt, nothing that interrupts play.
    private static let siblings: [(name: String, blurb: String, appID: String)] = [
        ("Just Kakuro", "Sums in a crossword grid", "6796701026"),
        ("Just Shikaku", "Cut the grid into rectangles", "6801529551"),
        ("Just Nurikabe", "Shade the sea around numbered islands", "6816718565"),
        ("Numeriqo", "Calcudoku, taught step by step", "6749287069"),
    ]

    private var siblingsSection: some View {
        Section {
            ForEach(Self.siblings, id: \.appID) { app in
                if let url = URL(string: "https://apps.apple.com/app/id\(app.appID)") {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).foregroundStyle(Theme.ink)
                            Text(app.blurb).font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .accessibilityHint("Opens the App Store")
                }
            }
        } header: {
            Text("More Just Puzzles").foregroundStyle(Theme.ink)
        }
    }

    /// Says which of restoring, restored, found-nothing and failed happened.
    /// Silence after a restore is indistinguishable from a broken button.
    ///
    /// No price here — quoting it would mean a second `loadProduct()` call site
    /// and a second chance to hardcode a number App Review will disagree with.
    private var storeFooter: String {
        switch entitlements.purchaseState {
        case .restoring:
            "Checking with the App Store…"
        case .note(let message):
            message
        case .failed(let message):
            message
        default:
            entitlements.isUnlocked
                ? "The full game is unlocked on this Apple Account."
                : "One purchase unlocks every lesson, every drill, the teaching hints, large boards, past dailies and stats. Already bought it? Restore brings it back on this device."
        }
    }
}
