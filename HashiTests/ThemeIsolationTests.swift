import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Hashi

// MARK: - Compile-time guard
//
// These helpers are `nonisolated` and synchronous. If `Theme` or `Motion` ever
// loses `nonisolated` and falls back to the project's MainActor default, every
// reference below becomes
//     "main actor-isolated static property 'x' can not be referenced from a
//      nonisolated context"
// and THE TEST TARGET FAILS TO BUILD. That is deliberate: the build breaks
// before the runtime guard below gets a chance to take the whole test runner
// down with a SIGTRAP.
//
// `nonisolated` on these functions is not optional. HashiTests inherits
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor from the project, so an unannotated
// helper would itself be MainActor-isolated and this guard would silently pass
// forever.

private nonisolated func nonisolatedThemeColors() -> [Color] {
    [Theme.sea, Theme.surface, Theme.island, Theme.islandRim, Theme.ink,
     Theme.inkSoft, Theme.inkOnIsland, Theme.bridge, Theme.bridgeGhost,
     Theme.bridgeWash, Theme.foam, Theme.vermillion, Theme.hairline]
}

private nonisolated func nonisolatedThemeFonts() -> [Font] {
    [Theme.title, Theme.heading,
     Theme.islandFont(size: 12), Theme.numberFont(size: 12)]
}

private nonisolated func nonisolatedMotionTokens() -> [Animation] {
    [Motion.bridgeDraw, Motion.bridgeSplit, Motion.bridgeClear,
     Motion.islandSettle, Motion.reject, Motion.selection, Motion.ripple,
     Motion.stamp, Motion.boardEntrance, Motion.hintPulse, Motion.overlay]
}

/// Marks the main queue so the runtime guard can prove it ran off it.
private nonisolated let mainQueueKey: DispatchSpecificKey<Bool> = {
    let key = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: key, value: true)
    return key
}()

/// Component extraction, so comparison does not depend on `UIColor.isEqual`.
private nonisolated func rgba(_ color: UIColor) -> [CGFloat] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

@Suite struct ThemeIsolationTests {

    /// Keeps the helpers above alive (an unused `nonisolated` function would be
    /// easy to delete, taking the compile-time guard with it) and keeps their
    /// token lists in sync with Theme/Motion.
    @Test func designTokensAreReachableFromANonisolatedContext() {
        #expect(nonisolatedThemeColors().count == 13)
        #expect(nonisolatedThemeFonts().count == 4)
        #expect(nonisolatedMotionTokens().count == 11)
        #expect(Motion.rippleStagger > 0)
        #expect(Motion.boardEntranceStagger > 0)
    }

    /// Runtime guard — backstop for the compile-time one.
    ///
    /// Resolves every Theme color off the main thread, in both trait styles.
    /// This is exactly what UIKit does from `com.apple.SwiftUI.AsyncRenderer`.
    /// If a Theme dynamic-color provider ever becomes actor-isolated again this
    /// does NOT fail politely: it traps (EXC_BREAKPOINT) and takes the whole
    /// test runner with it. That is the intended signal — Kakuro shipped
    /// exactly that crash, intermittently, even sitting idle on Home.
    ///
    /// Known environment quirk (inherited from Kakuro): under serial,
    /// non-cloned simulator runs the `UIColor(Color)` round-trip can lose its
    /// dynamic provider and this test fails spuriously. It passes under normal
    /// cloned parallel runs. Do not "fix" Theme because of it.
    @Test func dynamicColorsResolveOffTheMainThread() async {
        let tokens: [(String, Color)] = [
            ("sea", Theme.sea), ("surface", Theme.surface), ("island", Theme.island),
            ("islandRim", Theme.islandRim), ("ink", Theme.ink),
            ("inkSoft", Theme.inkSoft), ("bridge", Theme.bridge),
            ("bridgeGhost", Theme.bridgeGhost), ("bridgeWash", Theme.bridgeWash),
            ("foam", Theme.foam), ("vermillion", Theme.vermillion),
            ("hairline", Theme.hairline),
        ]
        // `inkOnIsland` is deliberately absent: it resolves identically in both
        // styles by design (island discs stay light), so the "was the provider
        // exercised" check below would flag it forever.

        // No #expect inside the detached task: Swift Testing tracks the current
        // test in a task-local, which Task.detached does not inherit, so issues
        // recorded in there would be unattributable. Return data, assert outside.
        let result = await Task.detached { () -> (onMain: Bool, differing: [String]) in
            let light = UITraitCollection(userInterfaceStyle: .light)
            let dark = UITraitCollection(userInterfaceStyle: .dark)
            var differing: [String] = []
            for (name, color) in tokens {
                let ui = UIColor(color)
                if rgba(ui.resolvedColor(with: light)) != rgba(ui.resolvedColor(with: dark)) {
                    differing.append(name)
                }
            }
            // `Thread.isMainThread` is unavailable from async contexts, so ask
            // dispatch directly whether we are on the main queue.
            let onMain = DispatchQueue.getSpecific(key: mainQueueKey) != nil
            return (onMain, differing)
        }.value

        #expect(!result.onMain, "guard is meaningless if this ran on the main thread")
        // If a token resolves identically in both styles the provider was never
        // really exercised, and this guard has quietly become a no-op.
        let inert = Set(tokens.map(\.0)).subtracting(result.differing).sorted()
        #expect(inert.isEmpty,
                "these tokens resolved identically in light and dark, so the dynamic provider was not exercised: \(inert)")
    }

    /// Catches the *class* of bug, which neither guard above can: a second
    /// `UIColor` dynamic provider added inside some other, MainActor-isolated
    /// type. Such a closure is invoked from SwiftUI's render thread and traps
    /// under Swift 6 executor checking.
    @Test func dynamicColorProvidersLiveOnlyInNonisolatedTheme() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HashiTests
            .deletingLastPathComponent()   // Hashi (repo root)
            .appendingPathComponent("Hashi")

        var offenders: Set<String> = []
        var themeSource = ""
        let files = FileManager.default.enumerator(at: sourceRoot,
                                                   includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("dynamicProvider") || text.contains("UIColor {") {
                offenders.insert(url.lastPathComponent)
            }
            if url.lastPathComponent == "Theme.swift" { themeSource = text }
        }

        #expect(offenders == ["Theme.swift"],
                "UIColor dynamic providers must live only in the nonisolated Theme: \(offenders.sorted())")
        #expect(themeSource.contains("nonisolated enum Theme"),
                "Theme must stay nonisolated or its color provider traps on the render thread")
    }
}
