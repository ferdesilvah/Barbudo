#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// App entry: the lobby, then the table.
public struct RootView: View {
    @State private var game: LocalGameController?

    public init() {}

    public var body: some View {
        ZStack {
            if let game {
                TableView(game: game) {
                    withAnimation(.spring(duration: 0.4)) { self.game = nil }
                }
                .transition(.move(edge: .trailing))
            } else {
                LobbyView { players in
                    let g = LocalGameController(playerCount: players)
                    withAnimation(.spring(duration: 0.4)) { game = g }
                    g.start()
                }
                .transition(.move(edge: .leading))
            }
        }
    }
}

/// Offline lobby for Milestone 2: pick how many at the table, then play against bots.
/// Milestone 4 adds the table code and invites from the design.
struct LobbyView: View {
    let onStart: (Int) -> Void
    @State private var players = 4

    var body: some View {
        ZStack {
            WoodTable()
            VStack(spacing: 22) {
                Spacer(minLength: 10)
                VStack(spacing: 6) {
                    BeardMascot().frame(width: 96, height: 96)
                    Text("Barbudo")
                        .font(Theme.display(52))
                        .foregroundStyle(Theme.cream)
                        .shadow(color: Theme.ink, radius: 0, x: 0, y: 4)
                        .shadow(color: Theme.ink, radius: 0, x: 2, y: 0)
                        .shadow(color: Theme.ink, radius: 0, x: -2, y: 0)
                    Text("El juego de cartas de la familia").darkPill()
                }

                RoundTablePreview(players: players)
                    .frame(width: 250, height: 250)
                    .animation(.spring(duration: 0.4, bounce: 0.4), value: players)

                VStack(spacing: 10) {
                    Text("¿Cuántos a la mesa?")
                        .font(Theme.display(17, .semibold))
                        .foregroundStyle(Theme.cream)
                        .shadow(color: Theme.ink.opacity(0.6), radius: 0, y: 2)
                    HStack(spacing: 10) {
                        ForEach(3...6, id: \.self) { n in
                            Button { players = n } label: {
                                Text("\(n)")
                                    .font(Theme.display(22, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 56, height: 48)
                                    .chunky(radius: 16, fill: n == players ? Theme.marigold : Theme.paper,
                                            drop: n == players ? 1 : 4)
                                    .offset(y: n == players ? 3 : 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(n) jugadores")
                        }
                    }
                    Text("\(Rules.schedule(playerCount: players).count) rondas · hasta \(52 / players) cartas")
                        .darkPill()
                }
                .sensoryFeedback(.selection, trigger: players)

                Spacer(minLength: 0)

                Button("¡A jugar!") { onStart(players) }
                    .buttonStyle(ChunkyButtonStyle(height: 56, fontSize: 21))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Seats around a little round table: you at the bottom, bots filling in.
struct RoundTablePreview: View {
    let players: Int

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle().fill(Theme.woodDark)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
                    .background(Circle().fill(Theme.ink.opacity(0.45)).offset(y: 6))
                    .frame(width: 190, height: 190)
                    .position(c)
                Circle().fill(Theme.runner)
                    .overlay(Circle().strokeBorder(Theme.terracotta, lineWidth: 5))
                    .overlay(Circle().strokeBorder(Theme.teal, lineWidth: 4).padding(-4))
                    .frame(width: 100, height: 100)
                    .position(c)
                ForEach(0..<players, id: \.self) { i in
                    let theta = Double.pi / 2 + 2 * Double.pi * Double(i) / Double(players)
                    let names = ["Tú", "Pablo", "Juan", "María", "Rosa", "Lucho"]
                    Avatar(initial: i == 0 ? "T" : String(names[i].prefix(1)),
                           colors: Theme.seatColors[i], size: 52)
                        .position(x: c.x + 100 * cos(theta), y: c.y + 100 * sin(theta))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The bearded mascot from the design.
struct BeardMascot: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 92
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let ink = GraphicsContext.Shading.color(Theme.ink)
            let lw = 3.5 * s

            let face = Path(ellipseIn: CGRect(x: 14 * s, y: 12 * s, width: 64 * s, height: 64 * s))
            ctx.fill(face, with: .color(Color(hex: 0xF6D2A8)))
            ctx.stroke(face, with: ink, lineWidth: lw)

            var beard = Path()
            beard.move(to: pt(14, 44))
            beard.addCurve(to: pt(46, 86), control1: pt(14, 70), control2: pt(28, 86))
            beard.addCurve(to: pt(78, 44), control1: pt(64, 86), control2: pt(78, 70))
            beard.addCurve(to: pt(46, 60), control1: pt(70, 56), control2: pt(60, 60))
            beard.addCurve(to: pt(14, 44), control1: pt(32, 60), control2: pt(22, 56))
            ctx.fill(beard, with: .color(Color(hex: 0x6B3E26)))
            ctx.stroke(beard, with: ink, style: StrokeStyle(lineWidth: lw, lineJoin: .round))

            var hair = Path()
            hair.move(to: pt(18, 30))
            hair.addCurve(to: pt(74, 30), control1: pt(24, 12), control2: pt(68, 12))
            hair.addCurve(to: pt(18, 30), control1: pt(62, 22), control2: pt(30, 22))
            ctx.fill(hair, with: .color(Color(hex: 0x6B3E26)))
            ctx.stroke(hair, with: ink, style: StrokeStyle(lineWidth: lw, lineJoin: .round))

            var stache = Path()
            stache.move(to: pt(30, 55))
            stache.addCurve(to: pt(46, 54), control1: pt(36, 49), control2: pt(42, 50))
            stache.addCurve(to: pt(62, 55), control1: pt(50, 50), control2: pt(56, 49))
            stache.addCurve(to: pt(46, 56), control1: pt(56, 59), control2: pt(50, 58))
            stache.addCurve(to: pt(30, 55), control1: pt(42, 58), control2: pt(36, 59))
            ctx.fill(stache, with: .color(Color(hex: 0x4A2A1A)))
            ctx.stroke(stache, with: ink, lineWidth: 2.5 * s)

            for x in [35.0, 57.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 3.6) * s, y: 34.4 * s, width: 7.2 * s, height: 7.2 * s)), with: ink)
            }
            for x in [26.0, 66.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 4.5) * s, y: 42.5 * s, width: 9 * s, height: 9 * s)),
                         with: .color(Color(hex: 0xE8927C).opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Lobby") { RootView() }
#endif
