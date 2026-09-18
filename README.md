# Barbudo

Multiplayer version of *Barbudo*, the González del Riego family card game.

## Status: Milestone 3 — online multiplayer in the browser

The main path is now **`web/`**: a Node server plus a browser client, so the family plays from
their phones with a shared link, without the App Store. See [`web/README.md`](web/README.md) to
run it locally or put it online for free.

The Swift packages below (rules engine + SwiftUI app) remain for a possible native app later;
both implementations follow the same rules and pass the same scenarios.

## Swift app (Milestone 2) — playable offline vs. bots

Run the app:

```
brew install xcodegen   # once
xcodegen                # makes Barbudo.xcodeproj from project.yml
open Barbudo.xcodeproj  # pick an iPhone simulator, ⌘R
```

No XcodeGen? In Xcode: File › New › Project › iOS App (SwiftUI) named Barbudo, then
File › Add Package Dependencies › Add Local… › this folder, link `BarbudoUI`, and replace the
generated `App` struct with `App/BarbudoApp.swift`.

### BarbudoUI (SwiftUI, iOS 17+)

| File | What it holds |
| --- | --- |
| `Theme.swift` | Palette, rounded type, the chunky outline + drop-shadow look, button styles |
| `TableDecor.swift` | Wood grain table and the woven runner |
| `CardView.swift` | Cards, card backs, deck with trump tucked underneath |
| `SeatBadge.swift` | Avatar, card count, name tag, bid chips (fichas) |
| `HandView.swift` | Fanned hand: sorted with trump last, legal cards lift on tap, tap again to play |
| `BidPanel.swift` | Bid picker; the hook rule's forbidden number is crossed out with a reason |
| `TableView.swift` | The table seen from your chair, 3–6 players, trick area, callouts, status hints |
| `ScoreViews.swift` | Handwritten scoresheet, end-of-round card, game-over card |
| `RootView.swift` | Lobby (pick 3–6 players), mascot, entry point |
| `LocalGameController.swift` | Runs the engine with bots, paces them, holds finished tricks on screen briefly |

The UI reads only `PlayerView`, so Milestone 4 can swap `LocalGameController` for a network
controller without touching the views.

**Fonts:** the design uses Fredoka, Nunito and Caveat (all SIL Open Font License). Until
they're added to the app bundle (`UIAppFonts`), the UI falls back to the rounded system font.

## Milestone 1 — rules engine

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

3. Vapor server (`BarbudoServer`) + `BarbudoProtocol` wire messages
4. Online rooms, reconnect, bot cover
