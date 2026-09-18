/// Pure rule functions. Each maps to one paragraph of the rulebook and is tested on its own.
public enum Rules {
    public static let minPlayers = 3
    public static let maxPlayers = 6

    /// Hand size per round: 1, 2, … M, then M repeated so every player deals it once.
    /// M = floor(52 / players). 4 players → 16 rounds, 5 → 14, 3 → 19, 6 → 13.
    public static func schedule(playerCount n: Int) -> [Int] {
        precondition((minPlayers...maxPlayers).contains(n), "Barbudo is for 3–6 players")
        let m = Card.fullDeck.count / n
        return Array(1...m) + Array(repeating: m, count: n - 1)
    }

    /// Legal bids for the player about to bid. `existingBids` are the bids already
    /// made this round; `playerCount` tells us whether this bidder is the last one.
    public static func legalBids(
        handSize: Int,
        existingBids: [Int],
        playerCount: Int,
        rules: RuleSet
    ) -> [Int] {
        var bids = Array(0...handSize)
        let isLastBidder = existingBids.count == playerCount - 1
        if rules.hookRule && isLastBidder {
            let forbidden = handSize - existingBids.reduce(0, +)
            bids.removeAll { $0 == forbidden }
        }
        return bids
    }

    /// Must follow the led suit if possible; otherwise any card (including trump: "chancar").
    public static func legalCards(
        hand: [Card],
        trick: [Play],
        trumpSuit: Suit?,
        trumpBroken: Bool,
        rules: RuleSet
    ) -> [Card] {
        guard let lead = trick.first else {
            if rules.mustBreakTrumpBeforeLeading, !trumpBroken, let trumpSuit {
                let nonTrump = hand.filter { $0.suit != trumpSuit }
                if !nonTrump.isEmpty { return nonTrump }
            }
            return hand
        }
        let following = hand.filter { $0.suit == lead.card.suit }
        return following.isEmpty ? hand : following
    }

    /// True if `challenger` beats the card currently winning the trick.
    /// The current best is always of the led suit or trump, so this is enough.
    public static func beats(_ challenger: Card, _ best: Card, trumpSuit: Suit?) -> Bool {
        if challenger.suit == best.suit { return challenger.rank > best.rank }
        return challenger.suit == trumpSuit
    }

    /// Index into `trick` of the winning play.
    public static func winningIndex(of trick: [Play], trumpSuit: Suit?) -> Int {
        precondition(!trick.isEmpty)
        var best = 0
        for i in trick.indices.dropFirst() where beats(trick[i].card, trick[best].card, trumpSuit: trumpSuit) {
            best = i
        }
        return best
    }

    /// Barbudo scoring:
    /// - exact with bid ≥ 1 → +bid
    /// - exact with bid 0 → +1
    /// - under → −bid
    /// - over → −tricks taken
    public static func score(bid: Int, took: Int) -> Int {
        if took == bid { return bid == 0 ? 1 : bid }
        if took < bid { return -bid }
        return -took
    }
}

public struct Play: Codable, Sendable, Hashable {
    public let seat: Int
    public let card: Card

    public init(seat: Int, card: Card) {
        self.seat = seat
        self.card = card
    }
}
