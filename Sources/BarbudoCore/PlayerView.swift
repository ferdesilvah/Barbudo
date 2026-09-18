/// What one seat is allowed to know. Built as a separate type (not a filtered
/// `GameState`) so secret fields — other hands, the stock, the RNG — can't leak
/// through the wire by accident. This is what the server sends to each client.
public struct PlayerView: Codable, Sendable, Hashable {
    public let seq: Int
    public let rules: RuleSet
    public let players: [Player]
    public let mySeat: Int?
    public let phase: Phase

    public let schedule: [Int]
    public let roundIndex: Int
    public let dealer: Int
    public let toAct: Int

    public let myHand: [Card]
    public let handCounts: [Int]
    public let trump: Card?
    public let trumpHolder: Int?
    public let bids: [Int?]
    public let tricksWon: [Int]
    public let trick: [Play]
    public let lastTrick: [Play]?

    public let seatDraws: [PlayerID: Card]
    public let roundScores: [[Int]]
    public let totals: [Int]

    /// Moves this seat can make right now. Empty when it's not this seat's turn.
    public let legalBids: [Int]
    public let legalCards: [Card]

    public var handSize: Int { schedule[roundIndex] }
    public var trumpSuit: Suit? { trump?.suit }
    public var isMyTurn: Bool { mySeat == toAct && [.cutting, .bidding, .playing].contains(phase) }
    public var bidTotal: Int { bids.compactMap { $0 }.reduce(0, +) }
}

extension GameState {
    /// Pass nil for a spectator view (no hand, no legal moves).
    public func view(for id: PlayerID?) -> PlayerView {
        let seat = id.flatMap { self.seat(of: $0) }
        return PlayerView(
            seq: seq,
            rules: rules,
            players: players,
            mySeat: seat,
            phase: phase,
            schedule: schedule,
            roundIndex: roundIndex,
            dealer: dealer,
            toAct: toAct,
            myHand: seat.map { hands[$0] } ?? [],
            handCounts: hands.map(\.count),
            trump: trump,
            trumpHolder: trumpHolder,
            bids: bids,
            tricksWon: tricksWon,
            trick: trick,
            lastTrick: lastTrick,
            seatDraws: seatDraws,
            roundScores: roundScores,
            totals: totals,
            legalBids: seat.map { legalBids(for: $0) } ?? [],
            legalCards: seat.map { legalCards(for: $0) } ?? []
        )
    }
}
