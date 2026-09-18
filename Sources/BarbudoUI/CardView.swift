#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// A chunky cartoon card. `card == nil` draws the terracotta back.
struct CardView: View {
    var card: Card?
    var width: CGFloat = 70

    private var scale: CGFloat { width / 70 }
    private var height: CGFloat { width * 10 / 7 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
        ZStack {
            if let card {
                shape.fill(Theme.paper)
                face(card)
            } else {
                shape.fill(Theme.terracotta)
                CrossHatch().clipShape(shape)
            }
            shape.strokeBorder(Theme.ink, lineWidth: 2.5 * max(scale, 0.7))
        }
        .frame(width: width, height: height)
        .background(shape.fill(Theme.ink.opacity(0.28)).offset(y: 4 * scale))
        .accessibilityElement()
        .accessibilityLabel(card.map { "\($0.rank.symbol) de \($0.suit.nombre)" } ?? "Carta boca abajo")
    }

    private func face(_ card: Card) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(card.rank.symbol).font(Theme.display(20 * scale))
                Text(card.suit.glyph).font(.system(size: 16 * scale))
            }
            .padding(.leading, 7 * scale)
            .padding(.top, 4 * scale)

            Text(card.suit.glyph)
                .font(.system(size: 34 * scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 8 * scale)
                .padding(.bottom, 6 * scale)
        }
        .foregroundStyle(Theme.color(for: card.suit))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Cream diamond lattice for card backs.
struct CrossHatch: View {
    var body: some View {
        Canvas { ctx, size in
            let color = Theme.cream.opacity(0.4)
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                for dir: CGFloat in [1, -1] {
                    var p = Path()
                    let start = dir > 0 ? x : x + size.height
                    p.move(to: CGPoint(x: start, y: 0))
                    p.addLine(to: CGPoint(x: start + dir * size.height, y: size.height))
                    ctx.stroke(p, with: .color(color), lineWidth: 3)
                }
                x += 10
            }
        }
    }
}

/// Face-down deck with the trump card tucked underneath, as on a real table.
struct DeckView: View {
    var trump: Card?
    var width: CGFloat = 70

    var body: some View {
        ZStack {
            if let trump {
                CardView(card: trump, width: width)
                    .rotationEffect(.degrees(90))
                    .offset(x: width * 0.45, y: width * 0.2)
            }
            ForEach(0..<3, id: \.self) { i in
                CardView(card: nil, width: width)
                    .offset(x: -CGFloat(i) * 1.5, y: -CGFloat(i) * 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trump.map { "Mazo. Triunfo: \($0.rank.symbol) de \($0.suit.nombre)" } ?? "Mazo")
    }
}

#Preview {
    HStack {
        CardView(card: Card(.ace, .spades))
        CardView(card: Card(.king, .hearts))
        CardView(card: nil)
        DeckView(trump: Card(.nine, .hearts)).padding(.leading, 30)
    }
    .padding(40)
    .background(Theme.wood)
}
#endif
