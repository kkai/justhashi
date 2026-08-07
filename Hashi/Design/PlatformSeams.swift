import SwiftUI

/// Sizes that differ because the screen is a different distance from the eye.
///
/// Just Hashi ships iPhone + iPad, but the tvOS seams are kept from its sibling
/// Kakuro — they cost nothing and encode lessons already paid for.
nonisolated enum Metrics {
    #if os(tvOS)
    static let glyph: CGFloat = 26
    static let column: CGFloat = 1100
    static let cellCap: CGFloat = 120
    static let selectionRing: CGFloat = 6
    static let wordmark: [CGFloat] = [120, 96, 76]
    static let stretchesSegments = false
    #else
    /// Small symbols: chevrons, close crosses, list badges.
    static let glyph: CGFloat = 13
    /// Reading column for iPad/large layouts.
    static let column: CGFloat = 560
    /// Board cell pitch ceiling.
    static let cellCap: CGFloat = 88
    /// Selected-island ring width.
    static let selectionRing: CGFloat = 2
    /// Wordmark candidates, largest first, for the `ViewThatFits` lockup.
    static let wordmark: [CGFloat] = [44, 38, 32]
    static let stretchesSegments = true
    #endif

    /// Minimum comfortable island hit target.
    static let islandHitTarget: CGFloat = 40

    /// How wide the board may grow. A phone board fills its width; an iPad has
    /// far more room than the reading column, and a 560pt board marooned in a
    /// 1024pt screen reads as a phone app someone stretched.
    static func boardWidth(regularWidth: Bool) -> CGFloat {
        regularWidth ? 760 : column
    }

    /// Cell pitch ceiling. Without a bigger cap on iPad, a 3×3 lesson board
    /// would stay phone-sized in the middle of a large screen.
    static func cellCap(regularWidth: Bool) -> CGFloat {
        regularWidth ? 130 : cellCap
    }
}

/// The app's button style everywhere.
///
/// On iOS this is effectively `.plain`: a custom style already replaces the
/// system chrome. The focus-aware brightness treatment is inherited from
/// Kakuro's tvOS build (where focus is the only cursor there is) and also
/// serves hardware-keyboard focus on iPad.
struct HashiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusAware(configuration: configuration)
    }

    private struct FocusAware: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .brightness(isFocused ? 0.18 : 0)
                .shadow(color: .black.opacity(isFocused ? 0.55 : 0),
                        radius: isFocused ? 20 : 0, y: isFocused ? 8 : 0)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(Motion.selection, value: isFocused)
        }
    }
}

extension ButtonStyle where Self == HashiButtonStyle {
    static var hashi: HashiButtonStyle { HashiButtonStyle() }
}

/// How a screen wants its navigation title sized. macOS has no equivalent of
/// `navigationBarTitleDisplayMode`; the enum keeps the iOS intent readable.
enum NavigationTitleDisplay {
    case large
    case inline
}

extension View {
    @ViewBuilder
    func navigationTitleDisplay(_ display: NavigationTitleDisplay) -> some View {
        #if os(iOS)
        switch display {
        case .large: navigationBarTitleDisplayMode(.large)
        case .inline: navigationBarTitleDisplayMode(.inline)
        }
        #else
        self
        #endif
    }

    /// Sheets are half-height cards on iOS, free-floating resizable panels on
    /// macOS, full screen on tvOS.
    @ViewBuilder
    func mediumSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
        #elseif os(tvOS)
        self
        #else
        frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

/// An explicit way out of a sheet. iOS lets you drag a sheet away, but a
/// visible close affordance is kinder — and on macOS a SwiftUI sheet is modal
/// with no drag gesture at all (Kakuro's first Mac build shipped a paywall
/// with no exit).
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(tvOS)
        button
        #else
        button.keyboardShortcut(.cancelAction)
        #endif
    }

    private var button: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Metrics.glyph, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .padding(Metrics.glyph * 0.75)
                .background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.hashi)
        .accessibilityLabel("Close")
    }
}

#if os(iOS)
/// Switches off the edge swipe-back for as long as it is on screen.
///
/// Drawing a bridge is a drag, and a drag that starts near the left edge is
/// indistinguishable from the system's interactive pop until it has already
/// begun. Losing your place mid-puzzle to a mis-started drag reads as the app
/// misbehaving, so on a board screen the Back button is the only way out.
///
/// **Restoring on disappear is the load-bearing half.** The recogniser belongs
/// to the `UINavigationController`, not to this screen, so leaving it disabled
/// would kill swipe-back everywhere else for the rest of the session.
struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        /// What the gesture was set to before this screen touched it, so the
        /// restore puts back the real previous value rather than assuming true.
        private var wasEnabled: Bool?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            wasEnabled = gesture.isEnabled
            gesture.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let wasEnabled {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = wasEnabled
            }
            wasEnabled = nil
        }
    }
}
#endif

extension View {
    /// Turns off the interactive pop gesture while this screen is showing.
    /// Use it on anything the player drags across.
    @ViewBuilder
    func swipeBackDisabled() -> some View {
        #if os(iOS)
        background(SwipeBackDisabler().frame(width: 0, height: 0).accessibilityHidden(true))
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing end of the navigation bar on iOS, the window toolbar's action
    /// area on macOS.
    static var primaryTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}
