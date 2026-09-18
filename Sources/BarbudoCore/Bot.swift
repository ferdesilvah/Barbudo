/// A bot sees only a `PlayerView`, exactly like a human client, so it can't cheat.
/// Used for solo play, for covering disconnected players, and for simulation tests.
public protocol BarbudoBot: Sendable {
    /// The action to take when `view.isMyTurn` (or during the seat draw). Nil if nothing to do.
    mutating func action(for view: PlayerView) -> Action?
}

/// v1 heuristic: bid by counting likely winners; play to hit the bid exactly.
public struct HeuristicBot: BarbudoBot {
    private var rng: SeededRNG

    public init(seed: UInt64) { rng = SeededRNG(seed: seed) }

    public mutating func action(for view: PlayerView) -> Action? {
        guard let me = view.mySeat else { return nil }
        switch view.phase {
        case .seatDraw:
            return view.seatDraws[view.players[me].id] == nil ? .drawSeatCard : nil
        case .cutting where view.isMyTurn:
            return .cut(at: Int.random(in: 1...51, using: &rng))
        case .bidding where view.isMyTurn:
            return .bid(chooseBid(view))
        case .playing where view.isMyTurn:
            return .play(chooseCard(view, me: me))
        default:
            return nil
        }
    }

    // MARK: Bidding

    func estimateTricks(_ view: PlayerView) -> Double {
        let trumpSuit = view.trumpSuit
        var estimate = 0.0
        for card in view.myHand {
            let suitLength = view.myHand.filter { $0.suit == card.suit }.count
            if card.suit == trumpSuit {
                estimate += card.rank >= .jack ? 0.9 : 0.4
            } else if card.rank == .ace {
                estimate += suitLength <= 4 ? 0.85 : 0.6
            } else if card.rank == .king {
                estimate += suitLength <= 3 ? 0.4 : 0.2
            }
        }
        // More players → each high card is less likely to hold up.
        return estimate * (4.0 / Double(max(view.players.count, 4))).squareRoot()
    }

    func chooseBid(_ view: PlayerView) -> Int {
        let target = estimateTricks(view)
        return view.legalBids.min { abs(Double($0) - target) < abs(Double($1) - target) } ?? 0
    }

    // MARK: Play

    /// Rough card strength: any trump beats any non-trump.
    func strength(_ card: Card, trumpSuit: Suit?) -> Int {
        (card.suit == trumpSuit ? 100 : 0) + card.rank.rawValue
    }

    func chooseCard(_ view: PlayerView, me: Int) -> Card {
        let legal = view.legalCards
        let trumpSuit = view.trumpSuit
        let byStrength = legal.sorted { strength($0, trumpSuit: trumpSuit) < strength($1, trumpSuit: trumpSuit) }
        let need = (view.bids[me] ?? 0) - view.tricksWon[me]

        guard !view.trick.isEmpty else {
            // Leading: go for it with the strongest card if we still need tricks,
            // otherwise lead the weakest.
            return need > 0 ? byStrength.last! : byStrength.first!
        }

        let best = view.trick[Rules.winningIndex(of: view.trick, trumpSuit: trumpSuit)].card
        let winners = byStrength.filter { Rules.beats($0, best, trumpSuit: trumpSuit) }
        let losers = byStrength.filter { !Rules.beats($0, best, trumpSuit: trumpSuit) }

        if need > 0 {
            // Win as cheaply as possible; if we can't, throw away the weakest card.
            return winners.first ?? byStrength.first!
        } else {
            // Avoid winning: dump the highest card that still loses.
            return losers.last ?? winners.first!
        }
    }
}
