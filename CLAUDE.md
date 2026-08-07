# CLAUDE.md — Just Hashi

iPhone/iPad puzzle game (iOS 18+) teaching Hashiwokakero (Bridges), modeled on Good Sudoku. Sibling of `../kakuro` — same architecture, same invariants. Deep engineering notes: `docs/ENGINEERING.md` (and `../kakuro/docs/ENGINEERING.md` for the lessons this project inherits).

## Critical invariants

- **Never edit project.pbxproj to add files.** `objectVersion 77` + `PBXFileSystemSynchronizedRootGroup`: every `.swift` file under `Hashi/` and `HashiTests/` joins the build automatically.
- **`Hashi/Engine/` is pure**: no SwiftUI/UIKit imports, every type `nonisolated` + `Sendable`. It must compile as a CLI: `swiftc -O -o bench Hashi/Engine/*.swift bench/main.swift` (bench output to stderr).
- **`Theme` and `Motion` are `nonisolated` — load-bearing.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide; a `UIColor(dynamicProvider:)` closure that inherits MainActor traps off-main (`EXC_BREAKPOINT`, intermittent, shipped in kakuro once). Guarded by `ThemeIsolationTests`; do not "fix".
- **No ViewModels.** `@Observable` (never ObservableObject), `@Environment` for services, view state as enums, `.task(id:)` for async effects.
- Every shipped puzzle is unique-solution AND fully solvable by `LogicalSolver` — enforced inside `HashiGenerator.generate`, not by convention.
- **All paid-tier gating lives in `FeatureGate`**, as pure `nonisolated` functions taking `unlocked:` explicitly. Add a gate there and call it; never scatter `isUnlocked` checks through views.
- `EntitlementSource.isOwned` returns `Bool?` — `nil` means "couldn't determine" and **must never downgrade** a cached entitlement. The `Transaction.updates` listener starts in `EntitlementStore.init`, not a view's `.task`.
- Paywalled rows stay **tappable** (they present the paywall); only mastery-locked rows are `.disabled`.
- The Daily puzzle is exempt from the board-size gate — the weekend schedule is `.large` and the Daily is free. See `FeatureGate.isDailyAvailable`.
- `Technique` enum declaration order is the source of truth for the solver loop, difficulty weights, hint escalation, tutorial sequence, and practice menu.
- Persistence: save on board change + scene backgrounding + disappear (never phase-change-only); `savedGame` is observable state, not a defaults read in a view body.

## Build & test

```bash
xcodebuild -project Hashi.xcodeproj -scheme Hashi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build
xcodebuild test -project Hashi.xcodeproj -scheme Hashi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
# iPad
xcodebuild test -project Hashi.xcodeproj -scheme Hashi -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.5'
```

Always pin `OS=` (this machine has 18.x and 26.x runtimes). If simulator cloning fails ("stuck in creation state"): `-destination 'id=<udid>' -parallel-testing-enabled NO`.

Fast engine iteration without the simulator:
```bash
swiftc -O -o bench Hashi/Engine/*.swift bench/main.swift && ./bench
```

## Layout

- `Hashi/App/` — @main, ContentView, Route navigation, HomeView
- `Hashi/Engine/` — models, LogicalSolver (powers hints), BacktrackingSolver (uniqueness only), HashiGenerator, Difficulty, DailySeed
- `Hashi/Game/` — HashiGame (@Observable @MainActor), BoardView/BoardLayout/BridgeGesture, PuzzleCache
- `Hashi/Teaching/` — HintEngine (nudge → technique → highlight → resolution), tutorial DSL + baked lesson boards, practice drills, MasteryTracker
- `Hashi/Design/` — Theme ("ukiyo-e sea" palette), Motion (named tokens only — no inline animation values in views), Haptics
- `Hashi/Persistence/` — ProgressStore (UserDefaults + Codable, versioned keys `hashi.*.v1`, `init(userDefaults:)` test seam)
- `Hashi/Store/` — the one-time unlock. `FeatureGate` (all gating as pure functions, no StoreKit), `EntitlementStore` (@Observable, StoreKit behind an `EntitlementSource` seam), `PaywallPresenter` + `PaywallView` + `LockedFeatureView`/`LockedFeaturePanel`
- `StoreKit/Hashi.storekit`, `tools/icon/generate_appicon.py` — repo root, **outside `Hashi/`**, because the synchronized root group ships anything under it inside the app bundle

## Conventions

Swift 6, Swift Testing (`@Suite`/`@Test`/`#expect`) in `HashiTests` hosted by the app. `struct` over `class`, classes `final`, no force unwraps. Team `8H42EZRCCP`, bundle `de.kaikunze.hashi`, display name "Just Hashi".
