import SwiftUI

/// The app's field: water with depth, rather than a flat fill.
///
/// `Theme.sea` was a single colour, which on a large dark board read as
/// near-black nothing behind a lattice of identical hairline arcs. Three
/// changes, and only the second is a new idea:
///
/// 1. a vertical gradient, lighter at the top, so it reads as looking out
///    across water rather than at a wall
/// 2. a soft pool of light behind the board, so the play area lifts off the
///    field instead of floating on it
/// 3. wave rows whose phase, length and amplitude vary with the row, and which
///    shrink and fade toward the horizon, so the texture reads as a surface
///    rather than as wallpaper
///
/// Everything here is static. There is nothing for Reduce Motion to switch
/// off, and nothing redraws while the player is thinking.
///
/// `Theme.sea` stays as the flat token for cards and sheet backgrounds, where
/// a gradient would fight the content sitting on it.
struct SeaBackground: View {
    /// Waves belong on the screens that show a board. Menus and lists get the
    /// gradient alone, so text always sits on a plain field.
    var waves = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.seaShallow, Theme.seaDeep],
                           startPoint: .top, endPoint: .bottom)
            // Centred slightly above the middle: the board sits above centre
            // once the header is accounted for, and light that lands on the
            // geometric centre looks half a screen low.
            RadialGradient(colors: [Theme.bridge.opacity(0.055), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: 460)
            if waves {
                WaveField()
            }
        }
        .ignoresSafeArea()
    }
}

/// Hairline swells. Deterministic, so the water does not reshuffle on every
/// redraw, but irregular enough not to read as a grid.
private struct WaveField: View {
    var body: some View {
        Canvas { context, size in
            // Rows are spaced from the bottom up so the horizon compresses:
            // near water is roomy, distant water is tight.
            var row = 0
            var y = size.height
            while y > -40 {
                let depth = max(0, min(1, y / size.height))   // 1 near, 0 far
                let spacing = 30 + 34 * depth
                let scale = 0.45 + 0.75 * depth
                // Opacity falls away toward the horizon so the texture never
                // competes with the board or the chrome above it.
                let fade = 0.25 + 0.75 * depth

                let dash = 16 * scale
                let stride = (150 + 90 * depth) * 0.55
                // A cheap deterministic hash of the row: enough to break the
                // lattice without any randomness that could differ per frame.
                let jitter = Double((row &* 2654435761) % 1000) / 1000
                var x = -stride * jitter

                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addQuadCurve(to: CGPoint(x: x + dash, y: y),
                                      control: CGPoint(x: x + dash / 2,
                                                       y: y - 3.4 * scale))
                    context.stroke(path,
                                   with: .color(Theme.hairline.opacity(fade)),
                                   lineWidth: max(0.6, scale))
                    // Vary the gap a little within the row too, so no row is a
                    // ruler of evenly spaced marks.
                    let wobble = Double(((row &+ Int(x)) &* 40503) % 100) / 100
                    x += stride * (0.72 + 0.56 * wobble)
                }
                y -= spacing
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
