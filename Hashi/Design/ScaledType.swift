import SwiftUI

/// `Theme.numberFont` that follows Dynamic Type. `Font.system(size:)` ignores
/// the user's text size; `@ScaledMetric` scales it with a text style.
private struct ScaledNumberFont: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(Theme.numberFont(size: size))
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func numberFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledNumberFont(size: size, relativeTo: style))
    }

    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, relativeTo: style))
    }
}
