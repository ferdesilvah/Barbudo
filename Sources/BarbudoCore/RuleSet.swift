/// Every point the rulebook leaves open is a flag here, so the family can change
/// house rules without code changes. Defaults match the design doc.
public struct RuleSet: Codable, Sendable, Hashable {
    /// What sets trump when every card is dealt (e.g. 4 players × 13 cards).
    public enum NoStockTrump: String, Codable, Sendable {
        /// Reveal the card at the cut point. It is still dealt normally and, with the
        /// deal order in the rulebook, always lands as the dealer's last card.
        case cutCard
        /// Play the round without trump.
        case noTrump
    }

    /// Ambiguity 1.
    public var noStockTrump: NoStockTrump = .cutCard
    /// Ambiguity 2: if true, trump can't be led until someone has played trump
    /// in this round (unless the leader holds only trump).
    public var mustBreakTrumpBeforeLeading: Bool = false
    /// Ambiguity 3: the last bidder may not make total bids == hand size.
    public var hookRule: Bool = true

    public init(
        noStockTrump: NoStockTrump = .cutCard,
        mustBreakTrumpBeforeLeading: Bool = false,
        hookRule: Bool = true
    ) {
        self.noStockTrump = noStockTrump
        self.mustBreakTrumpBeforeLeading = mustBreakTrumpBeforeLeading
        self.hookRule = hookRule
    }

    public static let standard = RuleSet()
}
