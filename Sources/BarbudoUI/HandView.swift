#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// The player's hand as a curved fan along the bottom edge, sorted by suit with trump
/// on the right. Legal cards can be tapped to lift; tapping a lifted card plays it.
/// Fits up to 17 cards (3-player max hand) on a 375 pt-wide phone.
struct HandView: View {
    let cards: [Card]
    let trumpSuit: Suit?
    /// nil = not our turn to play: everything is shown normally but inert.
    let legal: Set<Card>?
    @Binding var selected: Card?
    let onPlay: (Card) -> Void

    private let cardWidth: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let sorted = Self.sort(cards, trump: trumpSuit)
            let n = sorted.count
            let mid = CGFloat(n - 1) / 2
            let step = n > 1 ? min(46, (geo.size.width - cardWidth - 24) / CGFloat(n - 1)) : 0
            let angle = n > 1 ? min(5, 36 / max(mid, 1)) : 0

            ZStack {
                ForEach(Array(sorted.enumerated()), id: \.element) { i, card in
                    let d = CGFloat(i) - mid
                    let isLegal = legal?.contains(card) ?? true
                    let isSelected = card == selected
                    CardView(card: card, width: cardWidth)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.marigold, lineWidth: 4)
                                    .padding(-3)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { tap(card, isLegal: isLegal) }
                        .opacity(legal == nil || isLegal ? 1 : 0.5)
                        .rotationEffect(.degrees(Double(d * angle)), anchor: UnitPoint(x: 0.5, y: 1.4))
                        .offset(
                            x: d * step,
                            y: d * d * (n > 9 ? 1.2 : 3.2) + (isSelected ? -26 : 0) + (legal != nil && !isLegal ? 10 : 0)
                        )
                        .zIndex(Double(i))
                        .accessibilityAddTraits(legal != nil && isLegal ? .isButton : [])
                        .accessibilityHint(isSelected ? "Toca otra vez para tirarla" : "")
                        .sensoryFeedback(.selection, trigger: isSelected)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: selected)
            .animation(.spring(duration: 0.4), value: cards)
        }
    }

    private func tap(_ card: Card, isLegal: Bool) {
        guard legal != nil, isLegal else { return }
        if selected == card {
            onPlay(card)
            selected = nil
        } else {
            selected = card
        }
    }

    /// Suits grouped, alternating colors where possible, trump last; ranks ascending.
    static func sort(_ cards: [Card], trump: Suit?) -> [Card] {
        let baseOrder: [Suit] = [.spades, .diamonds, .clubs, .hearts]
        let order = baseOrder.filter { $0 != trump } + (trump.map { [$0] } ?? [])
        return cards.sorted {
            let a = order.firstIndex(of: $0.suit)!, b = order.firstIndex(of: $1.suit)!
            return a != b ? a < b : $0.rank < $1.rank
        }
    }
}
#endif
