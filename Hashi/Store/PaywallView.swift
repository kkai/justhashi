import SwiftUI

/// The one-time unlock. No subscription, no ads, no consumables — the pitch is
/// that this is the whole thing, once.
struct PaywallView: View {
    let context: PaywallContext

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                featureList
                purchaseControls
            }
            .padding(24)
            .frame(maxWidth: Metrics.column)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.sea)
        .presentationBackground(Theme.sea)
        .task {
            // A failure raised on another screen must not greet the player here.
            entitlements.clearTransientState()
            await entitlements.loadProduct()
        }
        .onChange(of: entitlements.isUnlocked) { _, unlocked in
            // This is what closes the sheet when an Ask to Buy is approved
            // later, with no purchase-completion callback anywhere.
            if unlocked { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(context.feature.headline)
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                // The only way out that does not involve buying something.
                SheetCloseButton()
            }
            Text(context.feature.pitch)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The full game includes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ForEach(PaidFeature.allCases) { feature in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: Metrics.glyph, weight: .bold))
                        .foregroundStyle(Theme.foam)
                    // Everything is listed regardless of which gate they hit;
                    // the one they hit is the one in ink.
                    Text(feature.headline)
                        .font(.subheadline)
                        .foregroundStyle(feature == context.feature ? Theme.ink : Theme.inkSoft)
                        .fontWeight(feature == context.feature ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await entitlements.purchase() }
            } label: {
                HStack {
                    if entitlements.purchaseState == .purchasing {
                        ProgressView().tint(Theme.island)
                    } else {
                        // Never hardcode the price — App Review rejects a button
                        // that disagrees with the product's real localized price.
                        Text(entitlements.product.map { "Unlock everything · \($0.displayPrice)" }
                             ?? "Unlock everything")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bridge))
                .foregroundStyle(Theme.island)
            }
            .buttonStyle(.hashi)
            // Both controls key off the same flag, so a purchase and a restore
            // can never be started on top of each other.
            .disabled(entitlements.purchaseState.isBusy)

            Text("One purchase. No subscription, no ads.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            Button {
                Task { await entitlements.restore() }
            } label: {
                HStack(spacing: 6) {
                    if entitlements.purchaseState == .restoring {
                        ProgressView().controlSize(.small)
                    }
                    Text(entitlements.purchaseState == .restoring
                         ? "Checking with the App Store…" : "Restore purchases")
                }
                .font(.footnote)
                .foregroundStyle(Theme.bridge)
            }
            .buttonStyle(.hashi)
            .disabled(entitlements.purchaseState.isBusy)

            statusLine
        }
    }

    /// One place for everything the store has to say, so a waiting state, a
    /// neutral note and a failure cannot each invent their own layout.
    @ViewBuilder
    private var statusLine: some View {
        switch entitlements.purchaseState {
        case .awaitingApproval:
            message("Sent for approval. The full game unlocks by itself once it is approved, "
                    + "and you can keep playing in the meantime.", color: Theme.ink)
        case .note(let text):
            message(text, color: Theme.inkSoft)
        case .failed(let text):
            message(text, color: Theme.vermillion)
        default:
            EmptyView()
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Empty state for a screen that is wholly behind the unlock.
struct LockedFeatureView: View {
    let feature: PaidFeature

    var body: some View {
        ZStack {
            SeaBackground()
            LockedFeaturePanel(feature: feature)
                .padding(32)
        }
    }
}

/// The same pitch, card-shaped, for a screen that also carries free content.
///
/// Stats needs this: its daily streak belongs to the free tier, so locking the
/// whole screen would hide data the player owns.
struct LockedFeaturePanel: View {
    let feature: PaidFeature
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.bridge)
            Text(feature.headline)
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            Text(feature.pitch)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("Unlock everything") {
                paywall.present(feature)
            }
            .font(.headline)
            .tint(Theme.bridge)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }
}
