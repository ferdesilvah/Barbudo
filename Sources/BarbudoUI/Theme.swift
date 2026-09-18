#if canImport(SwiftUI)
import SwiftUI
import BarbudoCore

/// The cozy-table look from the design canvas: warm wood, cream paper, ink outlines,
/// chunky offset shadows. Colors are muted on purpose so long sessions stay easy on the eyes.
enum Theme {
    static let ink = Color(hex: 0x3B2A20)
    static let cream = Color(hex: 0xFFF4E0)
    static let paper = Color(hex: 0xFFFBF2)
    static let wood = Color(hex: 0xB97A4B)
    static let woodDark = Color(hex: 0x8C5530)
    static let runner = Color(hex: 0xF6E7C8)
    static let terracotta = Color(hex: 0xD4643A)
    static let marigold = Color(hex: 0xF2B441)
    static let teal = Color(hex: 0x3F8A86)
    static let sage = Color(hex: 0x7FA77A)
    static let plum = Color(hex: 0x9A5B8A)
    static let dusk = Color(hex: 0x5B7DB1)
    static let redSuit = Color(hex: 0xC4432B)
    static let blackSuit = Color(hex: 0x2F2A36)
    static let muted = Color(hex: 0x7A5A44)
    static let faint = Color(hex: 0x9C8672)
    static let gain = Color(hex: 0x3F7A3A)
    static let loss = Color(hex: 0xB8412A)

    /// Avatar fill + initial color, assigned by join order.
    static let seatColors: [(fill: Color, text: Color)] = [
        (teal, cream), (sage, ink), (marigold, ink), (plum, cream), (terracotta, cream), (dusk, cream),
    ]

    // Fonts. The mockup uses Fredoka / Nunito / Caveat (all SIL OFL). Until they're bundled,
    // `.rounded` system type keeps the friendly feel; Font.custom falls back automatically.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func label(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    static func hand(_ size: CGFloat) -> Font {
        .custom("Caveat-Bold", size: size)
    }

    static func color(for suit: Suit) -> Color {
        suit == .hearts || suit == .diamonds ? redSuit : blackSuit
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Suit {
    /// U+FE0E forces text presentation so iOS never swaps in the emoji heart.
    var glyph: String { symbol + "\u{FE0E}" }
    var nombre: String {
        switch self {
        case .spades: "espadas"
        case .hearts: "corazones"
        case .diamonds: "diamantes"
        case .clubs: "tréboles"
        }
    }
}

extension Card {
    var label: String { rank.symbol + suit.glyph }
}

// MARK: - Chunky cartoon surfaces

/// Fill + ink outline + solid offset shadow: the signature look.
struct Chunky: ViewModifier {
    var radius: CGFloat
    var fill: Color
    var line: CGFloat = 2.5
    var drop: CGFloat = 4

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: line))
            .background(shape.fill(Theme.ink.opacity(0.35)).offset(y: drop))
    }
}

extension View {
    func chunky(radius: CGFloat = 16, fill: Color = Theme.cream, line: CGFloat = 2.5, drop: CGFloat = 4) -> some View {
        modifier(Chunky(radius: radius, fill: fill, line: line, drop: drop))
    }

    /// Small cream name tag / info pill.
    func pill(fill: Color = Theme.cream, text: Color = Theme.ink) -> some View {
        self.font(Theme.label())
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .chunky(radius: 12, fill: fill, line: 2, drop: 0)
    }

    /// Dark translucent pill used for bid/trick info on the wood.
    func darkPill() -> some View {
        self.font(Theme.label(13))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.ink.opacity(0.78)))
    }
}

/// Big terracotta (or cream) button that sinks into its shadow when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color = Theme.terracotta
    var text: Color = Theme.paper
    var height: CGFloat = 52
    var fontSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .font(Theme.display(fontSize))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: 3))
            .offset(y: configuration.isPressed ? 4 : 0)
            .background(shape.fill(Theme.ink).offset(y: 5))
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round cream icon button used in the header.
struct RoundIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(width: 46, height: 46)
                .chunky(radius: 23)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
#endif
