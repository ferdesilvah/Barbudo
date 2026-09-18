# Barbudo

Multiplayer iOS version of *Barbudo*, the González del Riego family card game.

## Status: Milestone 1 — rules engine

`BarbudoCore` is a pure Swift state machine for the full game: seat draw, cut, deal,
trump, bidding with the hook rule, trick play, and scoring. Zero dependencies; it builds
on iOS and on the Linux server unchanged.

```
swift test          # on a Mac with Xcode 16+, or any Swift 6 toolchain
```

Or open `Package.swift` in Xcode and press ⌘U.

## Layout

| File | What it holds |
| --- | --- |
| `Card.swift` | Suit, Rank (Ace high), Card, the 52-card deck |
| `SeededRNG.swift` | SplitMix64. Makes games replayable from seed + action log |
| `RuleSet.swift` | House-rule flags for every ambiguity in the rulebook |
| `Rules.swift` | Pure functions: schedule, legal bids, legal cards, trick winner, score |
| `Game.swift` | `GameState` (secret, server-only) and its reducer `apply(_:by:)` / `advance()` |
| `PlayerView.swift` | Redacted per-seat view sent to clients |
| `Bot.swift` | Heuristic bot that plays from a `PlayerView` only |

## Using the engine

```swift
var game = GameState(players: players, rules: .standard, seed: secureRandomSeed)
let events = try game.apply(.drawSeatCard, by: "pedro")  // throws GameError if illegal
let view = game.view(for: "pedro")                         // what Pedro's phone may see
// ... .cut(at:), .bid(n), .play(card) ...
try game.advance()                                         // server: leave results screen
```

Seats: `players[i + 1]` sits to the left (clockwise) of `players[i]`. After the seat draw,
`players` is reordered so seat 0 drew the highest card and deals round 1.

## House-rule defaults (confirm with the family)

- Full-deal rounds (no stock): the cut card is trump and is still dealt. With the rulebook's
  deal order it always ends up as the dealer's last card, visible to everyone.
- Trump may be led at any time.
- Hook rule applies to the last bidder (dealer) only.
- Tied seat-draw ranks redraw; a tied final score is a shared win.

## Next milestones

2. SwiftUI table vs. 3 bots, offline
3. Vapor server (`BarbudoServer`) + `BarbudoProtocol` wire messages
4. Online rooms, reconnect, bot cover
