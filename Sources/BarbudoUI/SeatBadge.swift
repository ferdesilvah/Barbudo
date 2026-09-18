#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// Everything the table shows about one player, pre-digested from `PlayerView`.
struct SeatInfo: Identifiable {
    let seat: Int
    let name: String
    let colors: (fill: Color, text: Color)
    let handCount: Int
    let bid: Int?
    let took: Int
    let isTurn: Bool
    let isDealer: Bool
    let showsTricks: Bool   // false while bidding: show "Pidió n" instead of "took de bid"

    var id: Int { seat }
    var initial: String { String(name.prefix(1)).uppercased() }
}

/// Round clay avatar with a mini card-back count, name tag, and bid chips ("fichas").
struct SeatBadge: View {
    let info: SeatInfo
    /// Which side the card-count sits on, so it points toward the table.
    var cardsOnLeading = false

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: cardsOnLeading ? .topLeading : .topTrailing) {
                Avatar(initial: info.initial, colors: info.colors, size: 62)
                    .overlay {
                        if info.isTurn {
                            Circle()
                                .strokeBorder(Theme.marigold, lineWidth: 4)
                                .padding(-7)
                                .scaleEffect(pulse ? 1.08 : 1)
                                .opacity(pulse ? 0.6 : 1)
                        }
                    }
                MiniBack(count: info.handCount)
                    .rotationEffect(.degrees(cardsOnLeading ? -12 : 12))
                    .offset(x: cardsOnLeading ? -16 : 16, y: 4)
            }
            .frame(width: 62, height: 62)

            HStack(spacing: 4) {
                Text(info.name)
                if info.isDealer {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityLabel("reparte")
                }
            }
            .pill()

            BidChips(bid: info.bid, took: info.took, showsTricks: info.showsTricks)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
        .accessibilityElement(children: .combine)
    }
}

struct Avatar: View {
    let initial: String
    let colors: (fill: Color, text: Color)
    var size: CGFloat = 62

    var body: some View {
        Text(initial)
            .font(Theme.display(size * 0.45))
            .foregroundStyle(colors.text)
            .frame(width: size, height: size)
            .background(Circle().fill(colors.fill))
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
            .background(Circle().fill(Theme.ink.opacity(0.35)).offset(y: 4))
    }
}

/// Tiny card back with the number of cards left in that hand.
struct MiniBack: View {
    let count: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.terracotta)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
            .frame(width: 24, height: 34)
            .overlay {
                Text("\(count)")
                    .font(Theme.display(12))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Theme.cream))
            }
            .accessibilityLabel("\(count) cartas")
    }
}

/// "Pidió 2 ●●" while bidding; "1 de 2 ●○" while playing. Filled chip = trick won.
struct BidChips: View {
    let bid: Int?
    let took: Int
    let showsTricks: Bool
    var onWood = true

    var body: some View {
        if let bid {
            let chips = max(bid, took)
            HStack(spacing: 4) {
                Text(showsTricks ? "\(took) de \(bid)" : (bid == 0 ? "Pasó" : "Pidió \(bid)"))
                HStack(spacing: -3) {
                    ForEach(0..<min(chips, 8), id: \.self) { i in
                        let filled = showsTricks ? i < took : true
                        Circle()
                            .fill(filled ? Theme.marigold : .clear)
                            .overlay(Circle().strokeBorder(onWood ? Theme.cream : Theme.ink, lineWidth: 2))
                            .frame(width: 13, height: 13)
                    }
                }
            }
            .darkPill()
        } else {
            Text("…").darkPill().opacity(0.6)
        }
    }
}
#endif
