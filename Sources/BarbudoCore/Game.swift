public typealias PlayerID = String

public struct Player: Codable, Sendable, Hashable, Identifiable {
    public let id: PlayerID
    public var name: String

    public init(id: PlayerID, name: String) {
        self.id = id
        self.name = name
    }
}

public enum Phase: String, Codable, Sendable {
    /// Everyone draws a card; highest sits first and deals round 1.
    case seatDraw
    /// Player to the dealer's right cuts; then the deal and trump reveal happen at once.
    case cutting
    case bidding
    case playing
    /// Results screen between rounds. The server calls `advance()` to continue.
    case roundScored
    case gameOver
}

public enum Action: Codable, Sendable, Hashable {
    case drawSeatCard
    /// Cut position in 1...51: the top `at` cards go to the bottom.
    case cut(at: Int)
    case bid(Int)
    case play(Card)
}

public enum GameEvent: Codable, Sendable, Hashable {
    case seatCardDrawn(player: PlayerID, card: Card)
    case seatDrawTied(players: [PlayerID])
    case seatsAssigned(order: [PlayerID])
    case roundStarted(round: Int, handSize: Int, dealer: Int)
    case deckCut(by: Int, at: Int)
    case cardsDealt(handSize: Int)
    /// `holder` is set when the trump card was dealt into someone's hand (no stock left).
    case trumpRevealed(card: Card?, holder: Int?)
    case bidPlaced(seat: Int, bid: Int)
    case cardPlayed(seat: Int, card: Card)
    case trickWon(seat: Int, trick: [Play])
    case roundScored(round: Int, deltas: [Int])
    case gameOver(winners: [Int])
}

public enum GameError: Error, Equatable, Sendable {
    case unknownPlayer
    case wrongPhase
    case notYourTurn
    case alreadyDrewSeatCard
    case invalidCut
    case illegalBid(allowed: [Int])
    case illegalCard
}

/// The full, secret game state. Only the server holds this; clients get a `PlayerView`.
/// Seats are indices into `players`; seat i+1 sits to the LEFT (clockwise) of seat i.
public struct GameState: Codable, Sendable, Hashable {
    public let rules: RuleSet
    public private(set) var players: [Player]
    public private(set) var phase: Phase = .seatDraw
    public private(set) var seq: Int = 0

    // Seat draw
    public private(set) var seatDraws: [PlayerID: Card] = [:]
    private var seatDeck: [Card]

    // Round
    public let schedule: [Int]
    public private(set) var roundIndex: Int = 0
    public private(set) var dealer: Int = 0
    public private(set) var toAct: Int = 0
    private var deck: [Card] = []
    public private(set) var hands: [[Card]]
    public private(set) var stock: [Card] = []
    public private(set) var trump: Card?
    /// Seat holding the face-up trump card when it was dealt (no-stock rounds); nil once played.
    public private(set) var trumpHolder: Int?
    public private(set) var trumpBroken = false
    public private(set) var bids: [Int?]
    public private(set) var tricksWon: [Int]
    public private(set) var trick: [Play] = []
    public private(set) var lastTrick: [Play]?

    // Score: roundScores[round][seat]
    public private(set) var roundScores: [[Int]] = []

    private var rng: SeededRNG

    public init(players: [Player], rules: RuleSet = .standard, seed: UInt64) {
        precondition((Rules.minPlayers...Rules.maxPlayers).contains(players.count), "Barbudo is for 3–6 players")
        precondition(Set(players.map(\.id)).count == players.count, "Player ids must be unique")
        self.rules = rules
        self.players = players
        self.schedule = Rules.schedule(playerCount: players.count)
        self.rng = SeededRNG(seed: seed)
        self.seatDeck = Card.fullDeck
        self.hands = Array(repeating: [], count: players.count)
        self.bids = Array(repeating: nil, count: players.count)
        self.tricksWon = Array(repeating: 0, count: players.count)
        self.seatDeck.shuffle(using: &rng)
    }

    // MARK: Derived

    public var playerCount: Int { players.count }
    public var handSize: Int { schedule[roundIndex] }
    public var trumpSuit: Suit? { trump?.suit }
    public var isLastRound: Bool { roundIndex == schedule.count - 1 }

    /// Seat to the dealer's right: cuts the deck.
    public var cutter: Int { (dealer + playerCount - 1) % playerCount }
    /// Seat to the dealer's left: gets the first card, bids first, leads first.
    public var firstToAct: Int { (dealer + 1) % playerCount }

    public var totals: [Int] {
        (0..<playerCount).map { seat in roundScores.reduce(0) { $0 + $1[seat] } }
    }

    public var winners: [Int] {
        guard phase == .gameOver, let best = totals.max() else { return [] }
        return totals.indices.filter { totals[$0] == best }
    }

    public func seat(of id: PlayerID) -> Int? { players.firstIndex { $0.id == id } }

    public func legalBids(for seat: Int) -> [Int] {
        guard phase == .bidding, seat == toAct else { return [] }
        return Rules.legalBids(
            handSize: handSize,
            existingBids: bids.compactMap { $0 },
            playerCount: playerCount,
            rules: rules
        )
    }

    public func legalCards(for seat: Int) -> [Card] {
        guard phase == .playing, seat == toAct else { return [] }
        return Rules.legalCards(
            hand: hands[seat], trick: trick, trumpSuit: trumpSuit,
            trumpBroken: trumpBroken, rules: rules
        )
    }

    // MARK: Reducer

    /// Apply a player's action. Throws without changing state if the action is illegal.
    @discardableResult
    public mutating func apply(_ action: Action, by id: PlayerID) throws -> [GameEvent] {
        guard let seat = seat(of: id) else { throw GameError.unknownPlayer }
        var events: [GameEvent] = []

        switch (phase, action) {
        case (.seatDraw, .drawSeatCard):
            guard seatDraws[id] == nil else { throw GameError.alreadyDrewSeatCard }
            let index = Int.random(in: 0..<seatDeck.count, using: &rng)
            let card = seatDeck.remove(at: index)
            seatDraws[id] = card
            events.append(.seatCardDrawn(player: id, card: card))
            if seatDraws.count == playerCount { resolveSeatDraw(&events) }

        case (.cutting, .cut(let at)):
            guard seat == toAct else { throw GameError.notYourTurn }
            guard (1..<Card.fullDeck.count).contains(at) else { throw GameError.invalidCut }
            cutAndDeal(at: at, &events)

        case (.bidding, .bid(let bid)):
            guard seat == toAct else { throw GameError.notYourTurn }
            let allowed = legalBids(for: seat)
            guard allowed.contains(bid) else { throw GameError.illegalBid(allowed: allowed) }
            bids[seat] = bid
            events.append(.bidPlaced(seat: seat, bid: bid))
            if bids.allSatisfy({ $0 != nil }) {
                phase = .playing
                toAct = firstToAct
            } else {
                toAct = (seat + 1) % playerCount
            }

        case (.playing, .play(let card)):
            guard seat == toAct else { throw GameError.notYourTurn }
            guard legalCards(for: seat).contains(card),
                  let handIndex = hands[seat].firstIndex(of: card)
            else { throw GameError.illegalCard }
            playCard(seat: seat, handIndex: handIndex, &events)

        default:
            throw GameError.wrongPhase
        }

        seq += 1
        return events
    }

    /// Server-driven: leave the results screen and start the next round (or end the game).
    @discardableResult
    public mutating func advance() throws -> [GameEvent] {
        guard phase == .roundScored else { throw GameError.wrongPhase }
        var events: [GameEvent] = []
        if isLastRound {
            phase = .gameOver
            events.append(.gameOver(winners: winners))
        } else {
            roundIndex += 1
            dealer = (dealer + 1) % playerCount
            startRound(&events)
        }
        seq += 1
        return events
    }

    // MARK: Phase steps

    private mutating func resolveSeatDraw(_ events: inout [GameEvent]) {
        // Tied ranks redraw (ambiguity 4). Only ties matter; suits don't rank.
        var byRank: [Rank: [PlayerID]] = [:]
        for (id, card) in seatDraws { byRank[card.rank, default: []].append(id) }
        let tied = byRank.values.filter { $0.count > 1 }.flatMap { $0 }
        if !tied.isEmpty {
            let ordered = players.map(\.id).filter { tied.contains($0) }
            for id in ordered { seatDraws[id] = nil }
            events.append(.seatDrawTied(players: ordered))
            // Plenty of cards: at most 6 players × a few redraws, and ties get rarer.
            if seatDeck.count < playerCount {
                seatDeck = Card.fullDeck.filter { !seatDraws.values.contains($0) }
                seatDeck.shuffle(using: &rng)
            }
            return
        }
        // Highest card sits first and deals round 1; others follow clockwise by value.
        let draws = seatDraws // local copy: can't read self while sorting self.players
        players.sort { draws[$0.id]!.rank > draws[$1.id]!.rank }
        events.append(.seatsAssigned(order: players.map(\.id)))
        dealer = 0
        startRound(&events)
    }

    private mutating func startRound(_ events: inout [GameEvent]) {
        deck = Card.fullDeck
        deck.shuffle(using: &rng)
        hands = Array(repeating: [], count: playerCount)
        stock = []
        trump = nil
        trumpHolder = nil
        trumpBroken = false
        bids = Array(repeating: nil, count: playerCount)
        tricksWon = Array(repeating: 0, count: playerCount)
        trick = []
        lastTrick = nil
        phase = .cutting
        toAct = cutter
        events.append(.roundStarted(round: roundIndex, handSize: handSize, dealer: dealer))
    }

    private mutating func cutAndDeal(at cut: Int, _ events: inout [GameEvent]) {
        // Cut: the top `cut` cards move to the bottom. The card at the cut point
        // (bottom of the lifted packet) becomes the last card of the deck.
        deck = Array(deck[cut...] + deck[..<cut])
        events.append(.deckCut(by: toAct, at: cut))

        // Deal one at a time, starting to the dealer's left.
        let dealt = handSize * playerCount
        let start = firstToAct
        let n = playerCount
        for i in 0..<dealt {
            hands[(start + i) % n].append(deck[i])
        }
        stock = Array(deck[dealt...])
        events.append(.cardsDealt(handSize: handSize))

        if let top = stock.first {
            // Flip the top of the remaining stock.
            trump = top
        } else {
            switch rules.noStockTrump {
            case .cutCard:
                // The cut card is deck.last, dealt last, i.e. to the dealer.
                trump = deck[deck.count - 1]
                trumpHolder = (start + dealt - 1) % n
            case .noTrump:
                trump = nil
            }
        }
        events.append(.trumpRevealed(card: trump, holder: trumpHolder))

        deck = []
        phase = .bidding
        toAct = firstToAct
    }

    private mutating func playCard(seat: Int, handIndex: Int, _ events: inout [GameEvent]) {
        let card = hands[seat].remove(at: handIndex)
        trick.append(Play(seat: seat, card: card))
        if card.suit == trumpSuit { trumpBroken = true }
        if card == trump, trumpHolder == seat { trumpHolder = nil }
        events.append(.cardPlayed(seat: seat, card: card))

        guard trick.count == playerCount else {
            toAct = (seat + 1) % playerCount
            return
        }

        let winner = trick[Rules.winningIndex(of: trick, trumpSuit: trumpSuit)].seat
        tricksWon[winner] += 1
        events.append(.trickWon(seat: winner, trick: trick))
        lastTrick = trick
        trick = []

        if hands[winner].isEmpty {
            let deltas = (0..<playerCount).map { Rules.score(bid: bids[$0] ?? 0, took: tricksWon[$0]) }
            roundScores.append(deltas)
            phase = .roundScored
            events.append(.roundScored(round: roundIndex, deltas: deltas))
        } else {
            toAct = winner
        }
    }
}
