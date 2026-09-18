import Testing
@testable import BarbudoCore

func makePlayers(_ n: Int) -> [Player] {
    ["Pedro", "Pablo", "Juan", "María", "Rosa", "Lucho"].prefix(n).map { Player(id: $0.lowercased(), name: $0) }
}

/// Drives a full game with bots, checking invariants after every step.
@discardableResult
func playFullGame(players n: Int, seed: UInt64, rules: RuleSet = .standard) throws -> GameState {
    var game = GameState(players: makePlayers(n), rules: rules, seed: seed)
    var bots: [PlayerID: HeuristicBot] = [:]
    for (i, p) in game.players.enumerated() { bots[p.id] = HeuristicBot(seed: seed &+ UInt64(i) &+ 1) }

    var steps = 0
    while game.phase != .gameOver {
        steps += 1
        #expect(steps < 10_000, "game did not terminate")
        if steps >= 10_000 { break }

        if game.phase == .roundScored {
            let tricks = game.tricksWon.reduce(0, +)
            #expect(tricks == game.handSize)
            try game.advance()
            continue
        }

        // Whoever can act: during the seat draw anyone who hasn't drawn; otherwise `toAct`.
        let actorID: PlayerID
        if game.phase == .seatDraw {
            actorID = game.players.first { game.seatDraws[$0.id] == nil }!.id
        } else {
            actorID = game.players[game.toAct].id
        }
        let view = game.view(for: actorID)
        let action = try #require(bots[actorID]!.action(for: view))
        let before = game.phase
        try game.apply(action, by: actorID)

        if before == .cutting {
            // Every card is accounted for right after the deal.
            #expect(game.hands.allSatisfy { $0.count == game.handSize })
            #expect(game.hands.map(\.count).reduce(0, +) + game.stock.count == 52)
            if game.stock.isEmpty, rules.noStockTrump == .cutCard {
                let holder = try #require(game.trumpHolder)
                #expect(holder == game.dealer)
                #expect(game.hands[holder].contains(game.trump!))
            }
        }
        if before == .bidding, game.phase == .playing, rules.hookRule {
            #expect(game.bids.compactMap { $0 }.reduce(0, +) != game.handSize)
        }
    }

    #expect(game.roundScores.count == game.schedule.count)
    #expect(!game.winners.isEmpty)
    return game
}

@Suite("Game")
struct GameTests {
    @Test("Bots finish full games with no illegal state", arguments: 3...6)
    func simulate(players: Int) throws {
        for seed in UInt64(1)...250 {
            try playFullGame(players: players, seed: seed)
        }
    }

    @Test func simulateHouseRuleVariants() throws {
        let variants = [
            RuleSet(noStockTrump: .noTrump),
            RuleSet(mustBreakTrumpBeforeLeading: true),
            RuleSet(hookRule: false),
        ]
        for rules in variants {
            for seed in UInt64(1)...50 { try playFullGame(players: 4, seed: seed, rules: rules) }
        }
    }

    @Test func sameSeedSameGame() throws {
        let a = try playFullGame(players: 4, seed: 42)
        let b = try playFullGame(players: 4, seed: 42)
        #expect(a == b)
    }

    @Test func dealerRotatesLeftAndFirstBidderIsLeftOfDealer() throws {
        var game = GameState(players: makePlayers(4), seed: 7)
        // Draw (and redraw ties) until seated.
        while game.phase == .seatDraw {
            for p in game.players where game.seatDraws[p.id] == nil { try game.apply(.drawSeatCard, by: p.id) }
        }
        #expect(game.dealer == 0)
        #expect(game.toAct == 3) // cutter = dealer's right
        try game.apply(.cut(at: 26), by: game.players[3].id)
        #expect(game.phase == .bidding)
        #expect(game.toAct == 1) // first bidder = dealer's left
    }

    @Test func illegalActionsThrowAndLeaveStateUntouched() throws {
        var game = GameState(players: makePlayers(3), seed: 3)
        let snapshot = game
        #expect(throws: GameError.wrongPhase) { try game.apply(.bid(0), by: "pedro") }
        #expect(throws: GameError.unknownPlayer) { try game.apply(.drawSeatCard, by: "nobody") }
        #expect(game == snapshot)
    }

    @Test func viewHidesOtherHands() throws {
        var game = GameState(players: makePlayers(4), seed: 11)
        while game.phase == .seatDraw {
            for p in game.players where game.seatDraws[p.id] == nil { try game.apply(.drawSeatCard, by: p.id) }
        }
        try game.apply(.cut(at: 10), by: game.players[game.toAct].id)
        let me = game.players[1].id
        let view = game.view(for: me)
        #expect(view.myHand == game.hands[1])
        #expect(view.handCounts == [1, 1, 1, 1])
        let spectator = game.view(for: nil)
        #expect(spectator.myHand.isEmpty && spectator.legalBids.isEmpty)
    }
}
