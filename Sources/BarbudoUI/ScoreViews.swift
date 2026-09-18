#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// The paper scoresheet, like the one the family keeps with a pencil:
/// rows = rounds, columns = players, running totals with the round's change beside them.
struct ScoresheetView: View {
    let view: PlayerView
    let colorIndex: [PlayerID: Int]
    @Environment(\.dismiss) private var dismiss

    private let rowHeight: CGFloat = 45

    var body: some View {
        ZStack {
            WoodTable()
            VStack(spacing: 18) {
                sheet
                    .rotationEffect(.degrees(-1.2))
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                Button("Volver a la mesa") { dismiss() }
                    .buttonStyle(ChunkyButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    private var totalsByRound: [[Int]] {
        var running = Array(repeating: 0, count: view.players.count)
        return view.roundScores.map { deltas in
            running = zip(running, deltas).map(+)
            return running
        }
    }

    private var sheet: some View {
        let totals = totalsByRound
        let best = view.totals.max() ?? 0
        return VStack(spacing: 0) {
            // spiral binding
            HStack {
                ForEach(0..<6, id: \.self) { _ in Circle().fill(Theme.ink).frame(width: 10, height: 10).frame(maxWidth: .infinity) }
            }
            .frame(height: 26)
            .background(Theme.terracotta)
            .overlay(alignment: .bottom) { Theme.ink.frame(height: 2.5) }

            HStack(alignment: .firstTextBaseline) {
                Text("Barbudo").font(Theme.hand(34))
                Spacer()
                Text("ronda \(view.roundIndex + 1) de \(view.schedule.count)")
                    .font(Theme.hand(22)).foregroundStyle(Theme.muted)
            }
            .padding(.leading, 72).padding(.trailing, 14).padding(.top, 6)

            ScrollView {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Text("ronda").font(Theme.hand(18)).foregroundStyle(Theme.muted).frame(width: 62)
                        ForEach(view.players.indices, id: \.self) { i in
                            Text(i == view.mySeat ? "Tú" : view.players[i].name)
                                .font(Theme.hand(24))
                                .foregroundStyle(headerColor(i))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: rowHeight)

                    ForEach(totals.indices, id: \.self) { r in
                        GridRow {
                            Text("\(r + 1)").font(Theme.hand(20)).foregroundStyle(Theme.muted).frame(width: 62)
                            ForEach(view.players.indices, id: \.self) { i in
                                scoreCell(total: totals[r][i], delta: view.roundScores[r][i],
                                          circled: r == totals.count - 1 && totals[r][i] == best)
                            }
                        }
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) { Theme.teal.opacity(0.28).frame(height: 2) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Text("exacto = +pedido · cero exacto = +1\ncorto = −pedido · pasado = −jugadas")
                .font(Theme.hand(20)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 72).padding(.vertical, 12)
        }
        .background(alignment: .leading) {
            Theme.terracotta.opacity(0.55).frame(width: 2).padding(.leading, 62)
        }
        .foregroundStyle(Theme.ink)
        .chunky(radius: 10, fill: Theme.paper, line: 2.5, drop: 8)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func scoreCell(total: Int, delta: Int, circled: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(signed(total, plus: false)).font(Theme.hand(26))
            Text(signed(delta, plus: true)).font(Theme.hand(17))
                .foregroundStyle(delta > 0 ? Theme.gain : Theme.loss)
        }
        .frame(maxWidth: .infinity)
        .overlay {
            if circled {
                Ellipse().stroke(Theme.terracotta, lineWidth: 2.5).padding(.horizontal, 4).rotationEffect(.degrees(-6))
            }
        }
    }

    private func headerColor(_ seat: Int) -> Color {
        let c = Theme.seatColors[(colorIndex[view.players[seat].id] ?? seat) % Theme.seatColors.count].fill
        return c == Theme.marigold ? Color(hex: 0x8A6412) : c   // darker gold stays legible on paper
    }

    private func signed(_ n: Int, plus: Bool) -> String {
        n < 0 ? "−\(-n)" : (plus ? "+\(n)" : "\(n)")
    }
}

/// Shown between rounds: who hit their bid, the points, and the running totals.
struct RoundResultsCard: View {
    let view: PlayerView
    let colorIndex: [PlayerID: Int]
    let onScores: () -> Void
    let onContinue: () -> Void

    var body: some View {
        let deltas = view.roundScores.last ?? []
        VStack(spacing: 14) {
            Text("Fin de la ronda \(view.roundIndex + 1)")
                .font(Theme.display(24))
            VStack(spacing: 8) {
                ForEach(view.players.indices, id: \.self) { i in
                    let p = view.players[i]
                    let colors = Theme.seatColors[(colorIndex[p.id] ?? i) % Theme.seatColors.count]
                    let delta = i < deltas.count ? deltas[i] : 0
                    HStack(spacing: 10) {
                        Avatar(initial: String(p.name.prefix(1)), colors: colors, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(i == view.mySeat ? "Tú" : p.name).font(Theme.label(15))
                            Text("Pidió \(view.bids[i] ?? 0) · se llevó \(view.tricksWon[i])")
                                .font(Theme.label(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(delta > 0 ? "+\(delta)" : "−\(-delta)")
                            .font(Theme.display(22))
                            .foregroundStyle(delta > 0 ? Theme.gain : Theme.loss)
                            .frame(width: 48, alignment: .trailing)
                        Text("\(view.totals[i])")
                            .font(Theme.display(18, .semibold))
                            .frame(width: 40)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.runner))
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Hoja", action: onScores)
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.cream, text: Theme.ink, fontSize: 18))
                    .frame(width: 110)
                Button("Seguir", action: onContinue)
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .chunky(radius: 24, fill: Theme.cream, line: 3, drop: 6)
    }
}

struct GameOverCard: View {
    let view: PlayerView
    let colorIndex: [PlayerID: Int]
    let onScores: () -> Void
    let onExit: () -> Void

    var body: some View {
        let best = view.totals.max() ?? 0
        let winners = view.players.indices.filter { view.totals[$0] == best }
        let names = winners.map { $0 == view.mySeat ? "Tú" : view.players[$0].name }
        VStack(spacing: 14) {
            HStack(spacing: -10) {
                ForEach(winners, id: \.self) { i in
                    Avatar(initial: String(view.players[i].name.prefix(1)),
                           colors: Theme.seatColors[(colorIndex[view.players[i].id] ?? i) % Theme.seatColors.count],
                           size: 72)
                }
            }
            Text(winners.count > 1 ? "¡Empate!" : (winners.first == view.mySeat ? "¡Ganaste!" : "¡Ganó \(names[0])!"))
                .font(Theme.display(30))
            Text(names.joined(separator: " y ") + " con \(best) puntos")
                .font(Theme.label(15)).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                Button("Hoja", action: onScores)
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.cream, text: Theme.ink, fontSize: 18))
                    .frame(width: 110)
                Button("Otra partida", action: onExit)
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(20)
        .chunky(radius: 24, fill: Theme.cream, line: 3, drop: 6)
        .sensoryFeedback(.success, trigger: best)
    }
}
#endif
