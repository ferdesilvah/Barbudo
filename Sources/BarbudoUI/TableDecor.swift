#if canImport(SwiftUI)
import SwiftUI

/// Honey-colored wooden table with soft vertical grain.
struct WoodTable: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.wood))
            let dark = Color(red: 0.35, green: 0.18, blue: 0.06).opacity(0.10)
            let light = Color(red: 1, green: 0.9, blue: 0.75).opacity(0.10)
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(dark))
                x += 38
            }
            x = 11
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(light))
                x += 23
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Woven table runner across the middle of the table: striped edges, zigzag band, plain center.
struct TableRunner: View {
    var body: some View {
        VStack(spacing: 0) {
            edge(flipped: false)
            Theme.runner
            edge(flipped: true)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func edge(flipped: Bool) -> some View {
        let stripes: [(Color, CGFloat)] = [(Theme.terracotta, 7), (Theme.marigold, 4), (Theme.teal, 7)]
        let ordered: [(Color, CGFloat)] = flipped ? Array(stripes.reversed()) : stripes
        VStack(spacing: 0) {
            if flipped { ZigzagBand(flipped: true).frame(height: 10) }
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                s.0.frame(height: s.1)
            }
            if !flipped { ZigzagBand(flipped: false).frame(height: 10) }
        }
    }
}

/// Diagonal woven pattern.
struct ZigzagBand: View {
    var flipped: Bool

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.runner))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                let dx = flipped ? -size.height : size.height
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + 4, y: 0))
                p.addLine(to: CGPoint(x: x + 4 + dx, y: size.height))
                p.addLine(to: CGPoint(x: x + dx, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(Theme.terracotta))
                x += 12
            }
        }
    }
}
#endif
