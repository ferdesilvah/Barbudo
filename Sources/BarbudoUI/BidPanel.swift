#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// "¿Cuántas te llevas?" — the bidding sheet. The hook rule's forbidden number is
/// shown crossed out with a one-line reason, so nobody thinks the app is broken.
struct BidPanel: View {
    let handSize: Int
    let legalBids: [Int]
    let bidTotal: Int
    let onBid: (Int) -> Void

    @State private var choice: Int?

    private var forbidden: Int? {
        (0...handSize).first { !legalBids.contains($0) }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: handSize + 1 <= 8 ? 4 : 6)
    }

    var body: some View {
        let current = choice ?? legalBids.min { abs($0 - handSize / 3) < abs($1 - handSize / 3) } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("¿Cuántas te llevas?")
                    .font(Theme.display(21, .semibold))
                Spacer()
                Text("Van \(bidTotal) de \(handSize)")
                    .font(Theme.label(13))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.marigold))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0...handSize, id: \.self) { n in
                    if n == forbidden {
                        forbiddenChip(n)
                    } else {
                        Button { choice = n } label: {
                            Text("\(n)")
                                .font(Theme.display(22, .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .chunky(radius: 16, fill: n == current ? Theme.marigold : Theme.paper,
                                        line: 2.5, drop: n == current ? 1 : 4)
                                .offset(y: n == current ? 3 : 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(n == current ? .isSelected : [])
                    }
                }
            }

            if let forbidden {
                Text("No puedes pedir \(forbidden): sumaría \(handSize) y alguien tiene que fallar.")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.muted)
            }

            Button(current == 0 ? "Pasar" : "Pedir \(current)") { onBid(current) }
                .buttonStyle(ChunkyButtonStyle())
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .chunky(radius: 22, fill: Theme.cream, line: 3, drop: 6)
        .animation(.spring(duration: 0.25, bounce: 0.4), value: choice)
        .sensoryFeedback(.selection, trigger: choice)
    }

    private func forbiddenChip(_ n: Int) -> some View {
        Text("\(n)")
            .font(Theme.display(22, .semibold))
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            )
            .overlay(
                Capsule().fill(Theme.redSuit).frame(height: 3).padding(.horizontal, 10).rotationEffect(.degrees(-18))
            )
            .accessibilityLabel("\(n), no permitido")
    }
}
#endif
