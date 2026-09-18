public enum Suit: String, CaseIterable, Codable, Sendable, Hashable {
    case clubs = "C", diamonds = "D", hearts = "H", spades = "S"

    public var symbol: String {
        switch self {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }
}

/// Ace is high: A > K > Q > J > 10 … 2.
public enum Rank: Int, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var symbol: String {
        switch self {
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        default: String(rawValue)
        }
    }
}

public struct Card: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, _ suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    public var description: String { rank.symbol + suit.symbol }

    /// The standard 52-card deck, no jokers, in a fixed order.
    public static let fullDeck: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card($0, suit) }
    }
}
