import Testing
@testable import BarbudoCore

@Suite("Rules")
struct RulesTests {
    // MARK: Round schedule (rulebook: "Desarrollo de las rondas")

    @Test("Round counts match the rulebook", arguments: [(3, 17, 19), (4, 13, 16), (5, 10, 14), (6, 8, 13)])
    func schedule(players: Int, maxHand: Int, rounds: Int) {
        let s = Rules.schedule(playerCount: players)
        #expect(s.count == rounds)
        #expect(s.max() == maxHand)
        #expect(Array(s.prefix(maxHand)) == Array(1...maxHand))
        #expect(s.suffix(players).allSatisfy { $0 == maxHand }) // max hand dealt once per player
    }

    // MARK: Scoring (rulebook: "Puntuación")

    @Test func scoring() {
        #expect(Rules.score(bid: 3, took: 3) == 3)  // exact
        #expect(Rules.score(bid: 0, took: 0) == 1)  // exact zero = 1 point
        #expect(Rules.score(bid: 3, took: 1) == -3) // under: lose the bid
        #expect(Rules.score(bid: 1, took: 4) == -4) // over: lose tricks taken
        #expect(Rules.score(bid: 0, took: 2) == -2)
    }

    /// The worked example in the rulebook: Pedro, Pablo, Juan, María over 3 rounds.
    /// Bids/tricks are one consistent reconstruction of the published deltas.
    @Test func rulebookExample() {
        let rounds: [[(bid: Int, took: Int)]] = [
            [(1, 0), (1, 1), (0, 0), (0, 0)], // round 1: −1, +1, +1, +1
            [(0, 0), (1, 1), (1, 0), (1, 1)], // round 2: +1, +1, −1, +1
            [(2, 2), (1, 0), (0, 1), (0, 0)], // round 3: +2, −1, −1, +1
        ]
        var totals = [0, 0, 0, 0]
        var table: [[Int]] = []
        for round in rounds {
            for (i, r) in round.enumerated() { totals[i] += Rules.score(bid: r.bid, took: r.took) }
            table.append(totals)
        }
        #expect(table == [[-1, 1, 1, 1], [0, 2, 0, 2], [2, 1, -1, 3]])
    }

    // MARK: Bidding (rulebook: "Fase de apuestas")

    @Test func hookRuleBlocksLastBidderOnly() {
        // Round 1, 4 players: total must not EQUAL the hand size (1).
        // After 0,0,0 the dealer can't bid 1.
        #expect(Rules.legalBids(handSize: 1, existingBids: [0, 0, 0], playerCount: 4, rules: .standard) == [0])
        // After 1,0,0 the dealer can't bid 0.
        #expect(Rules.legalBids(handSize: 1, existingBids: [1, 0, 0], playerCount: 4, rules: .standard) == [1])
        // Earlier bidders are unconstrained.
        #expect(Rules.legalBids(handSize: 3, existingBids: [3], playerCount: 4, rules: .standard) == [0, 1, 2, 3])
        // Forbidden number out of range → nothing removed.
        #expect(Rules.legalBids(handSize: 2, existingBids: [2, 2, 2], playerCount: 4, rules: .standard) == [0, 1, 2])
        // Hook disabled.
        let noHook = RuleSet(hookRule: false)
        #expect(Rules.legalBids(handSize: 1, existingBids: [0, 0, 0], playerCount: 4, rules: noHook) == [0, 1])
    }

    // MARK: Play (rulebook: "Juego" and "Valoración de las cartas")

    let hand = [Card(.ace, .spades), Card(.two, .hearts), Card(.king, .hearts), Card(.five, .clubs)]

    @Test func mustFollowSuit() {
        let trick = [Play(seat: 0, card: Card(.ten, .hearts))]
        let legal = Rules.legalCards(hand: hand, trick: trick, trumpSuit: .spades, trumpBroken: false, rules: .standard)
        #expect(Set(legal) == [Card(.two, .hearts), Card(.king, .hearts)])
    }

    @Test func voidInSuitMayPlayAnything() {
        let trick = [Play(seat: 0, card: Card(.ten, .diamonds))]
        let legal = Rules.legalCards(hand: hand, trick: trick, trumpSuit: .spades, trumpBroken: false, rules: .standard)
        #expect(Set(legal) == Set(hand))
    }

    @Test func leadingTrumpAllowedByDefault() {
        let legal = Rules.legalCards(hand: hand, trick: [], trumpSuit: .spades, trumpBroken: false, rules: .standard)
        #expect(legal.contains(Card(.ace, .spades)))
    }

    @Test func breakTrumpVariant() {
        let rules = RuleSet(mustBreakTrumpBeforeLeading: true)
        let legal = Rules.legalCards(hand: hand, trick: [], trumpSuit: .spades, trumpBroken: false, rules: rules)
        #expect(!legal.contains(Card(.ace, .spades)))
        let onlyTrump = [Card(.two, .spades)]
        #expect(Rules.legalCards(hand: onlyTrump, trick: [], trumpSuit: .spades, trumpBroken: false, rules: rules) == onlyTrump)
    }

    @Test func highestOfLedSuitWins() {
        let trick = [Play(seat: 0, card: Card(.ten, .hearts)),
                     Play(seat: 1, card: Card(.ace, .clubs)),   // off-suit ace is worthless
                     Play(seat: 2, card: Card(.queen, .hearts))]
        #expect(Rules.winningIndex(of: trick, trumpSuit: .spades) == 2)
    }

    @Test func anyTrumpBeatsLedSuit() { // "chancar"
        let trick = [Play(seat: 0, card: Card(.ace, .hearts)),
                     Play(seat: 1, card: Card(.two, .spades)),
                     Play(seat: 2, card: Card(.king, .hearts))]
        #expect(Rules.winningIndex(of: trick, trumpSuit: .spades) == 1)
    }

    @Test func highestTrumpWins() {
        let trick = [Play(seat: 0, card: Card(.ace, .hearts)),
                     Play(seat: 1, card: Card(.two, .spades)),
                     Play(seat: 2, card: Card(.jack, .spades)),
                     Play(seat: 3, card: Card(.three, .spades))]
        #expect(Rules.winningIndex(of: trick, trumpSuit: .spades) == 2)
    }

    @Test func noTrumpRound() {
        let trick = [Play(seat: 0, card: Card(.three, .hearts)),
                     Play(seat: 1, card: Card(.ace, .spades))]
        #expect(Rules.winningIndex(of: trick, trumpSuit: nil) == 0)
    }
}
