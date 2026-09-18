#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// The cozy table, seen from your chair: you at the bottom, everyone else around the
/// runner in clockwise order (the next player, who sits to your left, is on the left).
public struct TableView: View {
    let game: LocalGameController
    var onExit: () -> Void

    @State private var selected: Card?
    @State private var showScores = false

    public init(game: LocalGameController, onExit: @escaping () -> Void) {
        self.game = game
        self.onExit = onExit
    }

    public var body: some View {
        let v = game.view
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, playerCount: v.players.count, mySeat: v.mySeat ?? 0)
            ZStack {
                WoodTable()

                TableRunner()
                    .frame(width: geo.size.width + 40, height: layout.runnerHeight)
                    .position(layout.center)

                ForEach(opponentSeats(v), id: \.self) { seat in
                    let pos = layout.position(of: seat)
                    SeatBadge(info: info(seat, v), cardsOnLeading: pos.x > geo.size.width / 2)
                        .position(pos)
                }

                centerpiece(v, layout: layout)

                if let callout = game.callout {
                    CalloutBubble(text: callout.text)
                        .position(layout.calloutPosition(for: callout.seat))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .zIndex(5)
                }

                VStack(spacing: 10) {
                    header(v)
                    Spacer(minLength: 0)
                    actionArea(v)
                    statusRow(v)
                    HandView(
                        cards: v.myHand,
                        trumpSuit: v.trumpSuit,
                        legal: isMyPlayTurn(v) ? Set(v.legalCards) : nil,
                        selected: $selected,
                        onPlay: { game.play($0) }
                    )
                    .frame(height: 118)
                }
                .padding(.horizontal, 16)

                overlays(v)
            }
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showScores) {
            ScoresheetView(view: v, colorIndex: game.colorIndex)
                .presentationDetents([.large])
        }
        .onChange(of: v.seq) {
            if !isMyPlayTurn(game.view) { selected = nil }
        }
        .animation(.spring(duration: 0.35), value: game.callout)
    }

    // MARK: Pieces

    private func header(_ v: PlayerView) -> some View {
        HStack {
            RoundIconButton(systemName: "line.3.horizontal", label: "Menú", action: onExit)
            Spacer()
            Text("Ronda \(v.roundIndex + 1) de \(v.schedule.count) · \(v.handSize) \(v.handSize == 1 ? "carta" : "cartas")")
                .font(Theme.display(16, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .chunky(radius: 24, line: 2.5, drop: 4)
            Spacer()
            RoundIconButton(systemName: "list.bullet.clipboard", label: "Ver puntajes") { showScores = true }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func centerpiece(_ v: PlayerView, layout: TableLayout) -> some View {
        switch v.phase {
        case .cutting, .bidding:
            VStack(spacing: 14) {
                DeckView(trump: v.trump)
                    .onTapGesture { if v.phase == .cutting && v.isMyTurn { game.cut() } }
                    .accessibilityAddTraits(v.phase == .cutting && v.isMyTurn ? .isButton : [])
                if let trump = v.trump {
                    trumpTag(trump.suit, holder: v.trumpHolder.map { v.players[$0].name })
                }
            }
            .position(x: layout.center.x, y: layout.center.y + 6)
            .transition(.opacity)

        case .playing, .roundScored:
            ZStack {
                ForEach(game.displayedTrick, id: \.card) { play in
                    let o = layout.trickOffset(for: play.seat)
                    CardView(card: play.card)
                        .overlay {
                            if game.trickWinner == play.seat {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.marigold, lineWidth: 4).padding(-4)
                            }
                        }
                        .rotationEffect(.degrees(Double((play.seat * 37) % 17) - 8))
                        .offset(x: o.width, y: o.height)
                        .transition(.asymmetric(insertion: .offset(y: 60).combined(with: .opacity),
                                                removal: .scale(scale: 0.5).combined(with: .opacity)))
                }
                if let w = game.trickWinner {
                    Text(w == v.mySeat ? "¡Te la llevas!" : "Se la lleva \(v.players[w].name)")
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.ink))
                        .offset(y: 118)
                        .transition(.opacity)
                }
            }
            .position(layout.center)

            if let trump = v.trumpSuit {
                trumpTag(trump, holder: v.trumpHolder.map { v.players[$0].name })
                    .position(x: 64, y: layout.center.y + layout.runnerHeight / 2 - 34)
            }

        default:
            EmptyView()
        }
    }

    private func trumpTag(_ suit: Suit, holder: String?) -> some View {
        HStack(spacing: 5) {
            Text("Triunfo")
            Text(suit.glyph).foregroundStyle(Color(hex: 0xF28B6E))
            if let holder { Text("· la tiene \(holder)").font(Theme.label(12)) }
        }
        .font(Theme.display(14, .semibold))
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Theme.ink))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionArea(_ v: PlayerView) -> some View {
        if v.phase == .bidding && v.isMyTurn {
            BidPanel(handSize: v.handSize, legalBids: v.legalBids, bidTotal: v.bidTotal) { game.bid($0) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if isMyPlayTurn(v), let card = selected {
            Button("Tirar \(card.label)") {
                game.play(card)
                selected = nil
            }
            .buttonStyle(ChunkyButtonStyle())
            .frame(width: 190)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func statusRow(_ v: PlayerView) -> some View {
        let me = v.mySeat ?? 0
        let mine = info(me, v)
        return HStack(spacing: 8) {
            Avatar(initial: mine.initial, colors: mine.colors, size: 40)
                .overlay { if v.isMyTurn { Circle().strokeBorder(Theme.marigold, lineWidth: 4).padding(-5) } }
            Text(v.dealer == me ? "Tú · reparte" : "Tú").pill()
            if v.bids[me] != nil {
                BidChips(bid: v.bids[me], took: v.tricksWon[me], showsTricks: mine.showsTricks)
            }
            Spacer(minLength: 4)
            Text(hint(v))
                .font(Theme.display(15, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .chunky(radius: 14, fill: v.isMyTurn ? Theme.marigold : Theme.cream, line: 2, drop: 0)
        }
    }

    @ViewBuilder
    private func overlays(_ v: PlayerView) -> some View {
        if v.phase == .roundScored && !game.isPausing {
            Theme.ink.opacity(0.35).ignoresSafeArea().transition(.opacity)
            RoundResultsCard(view: v, colorIndex: game.colorIndex,
                             onScores: { showScores = true },
                             onContinue: { game.continueAfterRound() })
                .padding(20)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else if v.phase == .gameOver {
            Theme.ink.opacity(0.35).ignoresSafeArea()
            GameOverCard(view: v, colorIndex: game.colorIndex, onScores: { showScores = true }, onExit: onExit)
                .padding(20)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    // MARK: Helpers

    private func opponentSeats(_ v: PlayerView) -> [Int] {
        let me = v.mySeat ?? 0
        return (1..<v.players.count).map { (me + $0) % v.players.count }
    }

    private func isMyPlayTurn(_ v: PlayerView) -> Bool {
        v.phase == .playing && v.isMyTurn && !game.isPausing
    }

    private func info(_ seat: Int, _ v: PlayerView) -> SeatInfo {
        let p = v.players[seat]
        let colorIndex = game.colorIndex[p.id] ?? seat
        let active = [.cutting, .bidding, .playing].contains(v.phase) && !game.isPausing
        return SeatInfo(
            seat: seat,
            name: p.name,
            colors: Theme.seatColors[colorIndex % Theme.seatColors.count],
            handCount: v.handCounts[seat],
            bid: v.bids[seat],
            took: v.tricksWon[seat],
            isTurn: active && v.toAct == seat,
            isDealer: v.dealer == seat,
            showsTricks: v.phase == .playing || v.phase == .roundScored
        )
    }

    private func hint(_ v: PlayerView) -> String {
        let turnName = v.players[v.toAct].name
        switch v.phase {
        case .cutting:
            return v.isMyTurn ? "Toca el mazo para cortar" : "\(turnName) corta"
        case .bidding:
            return v.isMyTurn ? "Tu turno" : "Pide \(turnName)"
        case .playing:
            guard v.isMyTurn, !game.isPausing else { return "Juega \(turnName)" }
            guard let led = v.trick.first?.card.suit else { return "Tu salida" }
            return v.myHand.contains { $0.suit == led } ? "Sigue \(led.glyph)" : "Sin \(led.glyph): tira cualquiera"
        case .roundScored:
            return "Fin de la ronda"
        case .gameOver:
            return "Fin del juego"
        case .seatDraw:
            return "Sacando cartas…"
        }
    }
}

/// Where things sit on the table, for any 3–6 players.
struct TableLayout {
    let size: CGSize
    let playerCount: Int
    let mySeat: Int

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.40) }
    var runnerHeight: CGFloat { size.height * 0.36 }

    /// Opponents sit on an arc from your left (180°) over the top to your right (0°).
    private func angle(ofRelative k: Int) -> Double {
        playerCount == 2 ? 90 : 180 - 180 * Double(k - 1) / Double(playerCount - 2)
    }

    private func relative(_ seat: Int) -> Int { (seat - mySeat + playerCount) % playerCount }

    func position(of seat: Int) -> CGPoint {
        let theta = angle(ofRelative: relative(seat)) * .pi / 180
        let rx = size.width / 2 - 58
        let ry = max(center.y - 128, 60)
        return CGPoint(x: center.x + rx * cos(theta), y: center.y - 14 - ry * sin(theta))
    }

    /// Each played card lands just in front of whoever played it.
    func trickOffset(for seat: Int) -> CGSize {
        let k = relative(seat)
        guard k != 0 else { return CGSize(width: 0, height: 58) }
        let theta = angle(ofRelative: k) * .pi / 180
        return CGSize(width: 58 * cos(theta), height: -52 * sin(theta))
    }

    func calloutPosition(for seat: Int) -> CGPoint {
        let k = relative(seat)
        if k == 0 { return CGPoint(x: center.x, y: size.height - 205) }
        let p = position(of: seat)
        return CGPoint(x: min(max(p.x, 70), size.width - 70), y: p.y + 92)
    }
}

/// Cream speech bubble with a little tail: "¡Chancó!"
struct CalloutBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.display(16))
            .foregroundStyle(Theme.redSuit)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .chunky(radius: 14, fill: Theme.cream, line: 2.5, drop: 3)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.cream)
                    .frame(width: 12, height: 12)
                    .overlay(alignment: .topLeading) {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 12)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: 12, y: 0))
                        }
                        .stroke(Theme.ink, lineWidth: 2.5)
                    }
                    .rotationEffect(.degrees(45))
                    .offset(y: -6)
            }
    }
}
#endif
