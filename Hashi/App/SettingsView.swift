import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        @Bindable var progress = progress
        Form {
            Section("Play") {
                Toggle("Haptics", isOn: $progress.settings.hapticsEnabled)
                Toggle("Show mistakes", isOn: $progress.settings.showErrors)
            }
            Section {
                Toggle("Complete forced islands", isOn: $progress.settings.autoCompleteForced)
                Toggle("Show remaining count", isOn: $progress.settings.showRemainingCount)
            } footer: {
                Text("Complete forced islands draws bridges the first two techniques prove. Show remaining count replaces each island's number with how many bridges it still needs.")
            }
            storeSection
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
            Text("Just Hashi")
        } footer: {
            Text(storeFooter)
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
                : "One purchase unlocks every lesson, every drill, the teaching hints, large boards and stats. Already bought it? Restore brings it back on this device."
        }
    }
}
