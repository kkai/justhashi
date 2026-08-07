import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A light/dark colour value, held as plain components rather than a `UIColor`
/// or `NSColor`.
///
/// This is what lets the provider closure in `Theme.dynamic(light:dark:)` stay
/// `@Sendable` on both platforms: it captures only these, and whether a given
/// SDK declares its platform colour type `Sendable` stops mattering. See the
/// note on `Theme` for why that closure's annotations are load-bearing.
nonisolated struct ThemeRGBA: Sendable {
    let red, green, blue, alpha: CGFloat

    static let white = ThemeRGBA(red: 1, green: 1, blue: 1, alpha: 1)
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(_ c: ThemeRGBA) {
        self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#else
private extension NSColor {
    /// `srgbRed:` rather than `red:`, so the components land in the same colour
    /// space UIKit puts them in and the two platforms render identically.
    convenience init(_ c: ThemeRGBA) {
        self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#endif

/// Semantic color and type tokens. **Ukiyo-e sea**: Just Hashi is a woodblock
/// print of water — a pale sea-mist field, round paper islands like stones
/// above the waterline, bridges drawn in Prussian-blue ink, and one vermillion
/// seal-stamp red reserved for warnings and the win stamp. Rounded stamp-like
/// numerals, cool where its sibling Kakuro is warm.
///
/// `nonisolated` is load-bearing, not tidiness. The project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without it `Theme` — and the
/// provider closure in `dynamic(light:dark:)` — is implicitly `@MainActor`.
/// UIKit imports `-initWithDynamicProvider:` without `NS_SWIFT_SENDABLE`, so the
/// closure inherits that isolation and Swift 6 emits an executor assertion in
/// its prologue. UIKit resolves dynamic colors from SwiftUI's
/// `com.apple.SwiftUI.AsyncRenderer` thread, which trips the assertion and traps
/// (EXC_BREAKPOINT). It fired intermittently in Just Kakuro — anywhere,
/// including an idle Home screen — because whether a given resolve lands
/// off-main is a race. Guarded by ThemeIsolationTests.
nonisolated enum Theme {

    // MARK: - Colors (light / dark pairs)

    /// The field as a flat colour: cards, sheet backgrounds, anywhere a
    /// gradient would fight the content sitting on it. Full-screen backgrounds
    /// use `SeaBackground` instead, which has depth.
    static let sea = dynamic(light: ThemeRGBA(red: 0.918, green: 0.937, blue: 0.945, alpha: 1),
                             dark: ThemeRGBA(red: 0.043, green: 0.075, blue: 0.114, alpha: 1))
    /// Top of the sea gradient: light coming off the surface near the horizon.
    static let seaShallow = dynamic(light: ThemeRGBA(red: 0.933, green: 0.953, blue: 0.961, alpha: 1),
                                    dark: ThemeRGBA(red: 0.055, green: 0.102, blue: 0.157, alpha: 1))
    /// Bottom of it: the water nearest you, and the darkest part of the field.
    /// `sea` sits between the two, so nothing else in the palette shifts.
    static let seaDeep = dynamic(light: ThemeRGBA(red: 0.867, green: 0.902, blue: 0.918, alpha: 1),
                                 dark: ThemeRGBA(red: 0.024, green: 0.043, blue: 0.071, alpha: 1))
    /// Cards and sheets.
    static let surface = dynamic(light: .white,
                                 dark: ThemeRGBA(red: 0.106, green: 0.153, blue: 0.208, alpha: 1))
    /// Island discs — paper in both modes (moonlit stones at night), so island
    /// numerals always read ink-on-light. Use `inkOnIsland` for them.
    static let island = dynamic(light: .white,
                                dark: ThemeRGBA(red: 0.878, green: 0.890, blue: 0.867, alpha: 1))
    /// Island disc outline.
    static let islandRim = dynamic(light: ThemeRGBA(red: 0.075, green: 0.161, blue: 0.263, alpha: 0.85),
                                   dark: ThemeRGBA(red: 0.043, green: 0.075, blue: 0.114, alpha: 1))
    /// Primary text on `sea`/`surface`.
    static let ink = dynamic(light: ThemeRGBA(red: 0.075, green: 0.118, blue: 0.169, alpha: 1),
                             dark: ThemeRGBA(red: 0.886, green: 0.906, blue: 0.914, alpha: 1))
    /// Secondary text, quiet labels.
    static let inkSoft = dynamic(light: ThemeRGBA(red: 0.075, green: 0.118, blue: 0.169, alpha: 0.55),
                                 dark: ThemeRGBA(red: 0.886, green: 0.906, blue: 0.914, alpha: 0.55))
    /// Numerals on island discs — discs stay light in both modes, so this is
    /// the *light-mode* ink in both variants. Not a stylistic accident.
    static let inkOnIsland = dynamic(light: ThemeRGBA(red: 0.075, green: 0.118, blue: 0.169, alpha: 1),
                                     dark: ThemeRGBA(red: 0.075, green: 0.118, blue: 0.169, alpha: 1))
    /// Prussian blue — the ink the player draws with. Bridges, selection,
    /// interactive tint.
    static let bridge = dynamic(light: ThemeRGBA(red: 0.106, green: 0.259, blue: 0.427, alpha: 1),
                                dark: ThemeRGBA(red: 0.478, green: 0.639, blue: 0.812, alpha: 1))
    /// Drag preview of a bridge about to be drawn.
    static let bridgeGhost = dynamic(light: ThemeRGBA(red: 0.106, green: 0.259, blue: 0.427, alpha: 0.35),
                                     dark: ThemeRGBA(red: 0.478, green: 0.639, blue: 0.812, alpha: 0.4))
    /// Eligible-corridor glow and related highlights.
    static let bridgeWash = dynamic(light: ThemeRGBA(red: 0.106, green: 0.259, blue: 0.427, alpha: 0.12),
                                    dark: ThemeRGBA(red: 0.478, green: 0.639, blue: 0.812, alpha: 0.18))
    /// Sea foam: satisfied rings, completion sweeps.
    static let foam = dynamic(light: ThemeRGBA(red: 0.427, green: 0.647, blue: 0.616, alpha: 1),
                              dark: ThemeRGBA(red: 0.529, green: 0.749, blue: 0.702, alpha: 1))
    /// Hanko vermillion: errors, overfill, isolation warnings — and the win
    /// seal + streak mark. The two uses never share a screen.
    static let vermillion = dynamic(light: ThemeRGBA(red: 0.827, green: 0.290, blue: 0.196, alpha: 1),
                                    dark: ThemeRGBA(red: 0.914, green: 0.451, blue: 0.353, alpha: 1))
    /// Hairlines, grid dots, separators.
    static let hairline = dynamic(light: ThemeRGBA(red: 0.075, green: 0.118, blue: 0.169, alpha: 0.14),
                                  dark: ThemeRGBA(red: 0.886, green: 0.906, blue: 0.914, alpha: 0.14))

    /// The closure is *also* explicitly `@Sendable`. That is redundant while
    /// `Theme` is `nonisolated` — a `@Sendable` closure never inherits actor
    /// isolation — and deliberately so: either annotation alone prevents the
    /// executor-assertion prologue, so losing one does not silently bring the
    /// trap back. `dynamicProvider:` is spelled out rather than the trailing
    /// closure `UIColor { … }` so the dangerous API stays greppable.
    ///
    /// It captures `ThemeRGBA` values rather than platform colour objects, which
    /// is the third layer of the same protection: components are plainly
    /// `Sendable`, so the annotation above cannot be invalidated by whatever the
    /// SDK does or does not declare about `UIColor` and `NSColor`.
    private static func dynamic(light: ThemeRGBA, dark: ThemeRGBA) -> Color {
        #if canImport(UIKit)
        Color(UIColor(dynamicProvider: { @Sendable trait in
            UIColor(trait.userInterfaceStyle == .dark ? dark : light)
        }))
        #else
        // AppKit resolves against an NSAppearance rather than a trait
        // collection, and `bestMatch` is the documented way to ask a possibly
        // vibrant or accessibility appearance which of the two it counts as.
        Color(NSColor(name: nil, dynamicProvider: { @Sendable appearance in
            NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }))
        #endif
    }

    // MARK: - Type

    /// Island numerals: rounded, bold, stamp-like — monospaced digits so
    /// clues and capacities never shift as they change.
    static func islandFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Timers, counts.
    static func numberFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Display face for titles — rounded carries the wordmark.
    static let title = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let heading = Font.system(.title2, design: .rounded, weight: .semibold)
}
