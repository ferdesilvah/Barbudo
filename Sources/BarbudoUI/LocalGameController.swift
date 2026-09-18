#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// Runs a game on the phone: one human seat plus bots. It owns the full `GameState`
/// but the UI only ever reads `view` (the redacted `PlayerView`), exactly as it will
/// when the state lives on the server in Milestone 3. Swapping this for a network
/// controller should not change a single view.
@MainActor
@Observable
public final class LocalGameController {
    public private(set) var state: GameState
    public let humanID: PlayerID

    /// Cards to draw in the middle of the table. Holds a finished trick for a moment
    /// so everyone can see who won it before it's swept away.
    public private(set) var displayedTrick: [Play] = []
    public private(set) var trickWinner: Int?
    public private(set) var isPausing = false
    /// Short table-talk bubble, e.g. "¡Chancó!" over the player who trumped.
    public private(set) var callout: Callout?

    public struct Callout: Equatable, Sendable {
        public let seat: Int
        public let text: String
    }

    /// Stable color per player, by join order (seats get reshuffled by the draw).
    public let colorIndex: [PlayerID: Int]

    public var botDelay: Duration = .milliseconds(750)
    public var trickPause: Duration = .milliseconds(1300)

    private var bots: [PlayerID: HeuristicBot] = [:]
    private var loop: Task<Void, Never>?

    public init(playerCount: Int, humanName: String = "Tú", seed: UInt64 = .random(in: .min ... .max)) {
        let names = ["Pablo", "Juan", "María", "Rosa", "Lucho"]
        var players = [Player(id: "me", name: humanName)]
        for i in 0..<(playerCount - 1) {
            players.append(Player(id: "bot\(i)", name: names[i]))
        }
        state = GameState(players: players, seed: seed)
        humanID = "me"
        colorIndex = Dictionary(uniqueKeysWithValues: players.enumerated().map { ($1.id, $0) })
        for (i, p) in players.enumerated() where p.id != "me" {
            bots[p.id] = HeuristicBot(seed: seed &+ UInt64(i) &* 7919)
        }
    }

    public var view: PlayerView { state.view(for: humanID) }

    // MARK: Human actions

    /// Everyone draws for seats (instant in the offline game), then play begins.
    public func start() {
        while state.phase == .seatDraw {
            for p in state.players where state.seatDraws[p.id] == nil {
                _ = try? state.apply(.drawSeatCard, by: p.id)
            }
        }
        resumeBots()
    }

    public func cut() {
        perform(.cut(at: Int.random(in: 8...44)))
    }

    public func bid(_ n: Int) {
        perform(.bid(n))
    }

    public func play(_ card: Card) {
        perform(.play(card))
    }

    public func continueAfterRound() {
        guard state.phase == .roundScored else { return }
        withAnimation(.spring(duration: 0.4)) {
            _ = try? state.advance()
            displayedTrick = []
            trickWinner = nil
        }
        resumeBots()
    }

    // MARK: Engine plumbing

    private func perform(_ action: Action) {
        guard !isPausing else { return }
        withAnimation(.spring(duration: 0.35)) {
            apply(action, by: humanID)
        }
        resumeBots()
    }

    private func apply(_ action: Action, by id: PlayerID) {
        let ledSuit = state.trick.first?.card.suit
        let trumpSuit = state.trumpSuit
        guard let events = try? state.apply(action, by: id) else { return }
        callout = nil
        for event in events {
            switch event {
            case .cardPlayed(let seat, let card):
                guard let trumpSuit, card.suit == trumpSuit else { break }
                if ledSuit == nil {
                    callout = Callout(seat: seat, text: "¡Arrastró!")   // led trump
                } else if ledSuit != trumpSuit {
                    callout = Callout(seat: seat, text: "¡Chancó!")    // trumped a side suit
                }
            case .trickWon(let seat, let trick):
                displayedTrick = trick
                trickWinner = seat
                isPausing = true
            default:
                break
            }
        }
        if !isPausing { displayedTrick = state.trick }
    }

    private func resumeBots() {
        loop?.cancel()
        loop = Task { [weak self] in
            await self?.runBots()
        }
    }

    private func runBots() async {
        while !Task.isCancelled {
            if isPausing {
                try? await Task.sleep(for: trickPause)
                withAnimation(.spring(duration: 0.45)) {
                    isPausing = false
                    displayedTrick = state.trick
                    trickWinner = nil
                    callout = nil
                }
                continue
            }
            guard [.cutting, .bidding, .playing].contains(state.phase) else { return }
            let actor = state.players[state.toAct].id
            guard actor != humanID, var bot = bots[actor] else { return }

            try? await Task.sleep(for: botDelay)
            if Task.isCancelled { return }
            guard let action = bot.action(for: state.view(for: actor)) else { return }
            bots[actor] = bot
            withAnimation(.spring(duration: 0.35)) {
                apply(action, by: actor)
            }
        }
    }
}
#endif
