# Engineering notes — Just Hashi

Working notes: architecture, invariants, and inherited lessons. Just Hashi is
the sibling of Just Kakuro (`../../kakuro`); most invariants here were paid for
there — read `../../kakuro/docs/ENGINEERING.md` for their full origin stories.

## Project overview

iPhone/iPad puzzle game (iOS 18+) that teaches Hashiwokakero the way Good
Sudoku teaches sudoku: an interactive rules tutorial, an eight-technique
curriculum, an escalating hint engine that names and explains techniques,
per-technique practice drills with mastery tracking, and busywork reduction
(capacity rings, illegal-move prevention, isolation warnings, optional
auto-complete of forced islands).

### Hashi rules

Numbered islands (1–8) connect with horizontal/vertical bridges. Max two per
island pair; bridges may not cross bridges or islands; each island's number is
its exact bridge count; everything must form one connected network. Exactly one
solution per puzzle.

### Technique curriculum (order = source of truth)

`Technique` enum: fullIsland → onlyNeighbor → oneEachWay → capacityCount →
isolationGuard → segmentLink → oneStepContradiction → deepContradiction.
Declaration order drives the solver loop, difficulty weights, hint escalation,
tutorial sequence, and practice menu.

## Build & test

```bash
xcodebuild test -project Hashi.xcodeproj -scheme Hashi -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
# Engine iteration without the simulator (also proves engine purity):
swiftc -O -o bench Hashi/Engine/*.swift bench/main.swift && ./bench   # smoke|calibrate|audit|time
```

Always pin `OS=` (18.x and 26.x runtimes coexist here). Simulator cloning
failures: fall back to `-destination 'id=<udid>' -parallel-testing-enabled NO`.

## Architecture

Single Xcode project, objectVersion 77, `PBXFileSystemSynchronizedRootGroup` —
**never edit project.pbxproj to add files**.

- `Engine/` — pure logic, no SwiftUI/UIKit imports, everything `nonisolated`
  `Sendable`. Islands and edges are index-identified; solver hot paths are flat
  `Int8` arrays.
- Edge model: every geometrically possible corridor is materialized up front
  (`HashiPuzzle.build`), including ones the solution leaves empty. Crossings
  precomputed via span-cell intersection.
- `LogicalSolver` — bounds (`mins`/`maxs` per edge) + curriculum-ordered
  detectors. **Crossing exclusion is rule knowledge, not a technique**: the UI
  physically prevents crossings, so `normalize` applies it silently and no
  hint ever has to explain it.
- `LogicalSolver.hintChain` exists because max-cap deductions never appear in
  the player's board: a board-state query must chase the chain until a step
  *places a bridge*, or hints/mastery would loop on invisible knowledge.
  (Found by test on day one; the naive `nextStep(board:)` looped forever.)
- `BacktrackingSolver.countSolutions(limit: 2)` proves uniqueness only. It
  returns the found solutions so the generator's repair step can diff them.

## Generation

Spanning-structure-first: grow a connected bridge network by random walks, add
cycle bridges (trees are trivially solvable — cycles create the hard
deductions), derive clues from degrees, then verify **unique AND solvable at
the band's technique ceiling** in a single exit. Non-unique boards are repaired
by perturbing a differing edge (1↔2 flip or 0→1 add) and re-verifying — the
Kakuro `mutate()` insight; it converges fast for Hashi.

- Node budget (not wall clock) bounds the search; per-seed determinism is
  asserted by tests. **Never reorder an RNG draw** — dailies are a pure
  function of the seeded stream.
- Fallback: unlike Kakuro (whose fills are ~never unique, hence baked grids),
  Hashi search is cheap and repair converges, so the fallback is a **re-search
  with a proven seed** (`fallbackSeed`), pinned per size/difficulty by
  `fallbackSeedProducesVerifiedPuzzles`.
- Measured native -O: p50 well under 2ms everywhere; worst ~10ms
  (large). Debug simulator ≈25× slower on this engine; perf budget is 3s for
  a 9-generation sweep.
- Difficulty thresholds (p33/p66, bench `calibrate`, 2026-08-07):
  small 29/35, medium 52/66, large 102/119. Recalibrate whenever generation
  density, growth parameters, or rater weights change.

## The shadowing audit (inherited phenomenon, measured here)

Across 108 generated boards: `segmentLink` and `deepContradiction` appear in
**zero** solve traces (capacity arithmetic + isolation reach the same corridors
first); `oneStepContradiction` in ~10%. Consequences, same as Kakuro's:

- Their drills cannot be found by search → `PracticeDrills.handAuthored`
  = [segmentLink, oneStepContradiction, deepContradiction], baked boards shared
  with their lessons. `handAuthoredTechniquesAreUnsearchable` pins the premise.
- They can't be credited through play → their route to Learned is drills.
- Their *lessons* still teach the reasoning (scripted narration on hand-built
  boards); the engine's stronger arithmetic just gets there first in the wild.

## Tutorials

All nine lessons (rules + 8 techniques) are **hand-authored and baked** —
never generated. `TutorialPuzzles.bakedTechniques` is the source of truth;
`TutorialFixtureTests` proves every board unique + curriculum-solvable, every
`requireBridge` consistent with the unique solution, and **walks every lesson
through `TutorialEngine`** exactly as a player would. Scripts reference
corridors via `edge(puzzle, a, b)` lookup, never hard-coded edge ids.

The engine filters all board input (`handleTapIsland`/`handleCycleEdge`) — a
lesson that can be walked out from under was Kakuro's hardest tutorial bug.

## Mastery: the curriculum is a ladder with no holes

`recordBridge` credits the **hardest technique in the deduction chain**, which
can skip ahead of where the player formally is. Without
`introduceEarlier(than:)` that left the Practice list showing "Counting"
unlocked above a locked "One Each Way" — visibly broken progression. Any path
that introduces or promotes a technique must also unlock everything before it.
Caught by driving the app, not by tests; now pinned by
`creditingALaterTechniqueLeavesNoLockedGap`.

Mastery credit is claimed **once per corridor per game**
(`HashiGame.claimMasteryCredit(edge:)`), so draw/undo/redraw cannot farm a
technique to Learned. A visible hint at any level makes the move aided.

## Actor isolation in `Design/`

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide; `Theme` and `Motion`
are `nonisolated` and that is **load-bearing** (UIColor dynamicProvider trap,
EXC_BREAKPOINT off-main — shipped in Kakuro, intermittent, anywhere). Guarded
three ways by `ThemeIsolationTests`, including a source scan. `Haptics` must
STAY `@MainActor`. Known quirk: the off-main resolve test can fail under
serial non-cloned runs — pre-existing environment issue, do not "fix" Theme.

`inkOnIsland` resolves identically in light and dark **by design** (island
discs stay paper in both modes); it is deliberately excluded from the
"provider was exercised" check.

## UI notes

- One gesture owns the board: drag-from-island (direction-snapped, ghost
  preview) or tap-a-corridor; both cycle 0→1→2→0. Blocked corridors wiggle +
  error haptic and change nothing.
- **Touch-down must not pre-select** — selection on gesture start plus
  toggle-on-tap = tap deselects instantly. Selection is set only once a real
  drag begins; taps go through `onTapIsland`. (Caught on-device.)
- `BoardLayout` is the single grid↔point source of truth for the bridge
  Canvas, the island views, and hit-testing. Its `cellCap` is size-class aware:
  without a larger cap on iPad a 3×3 lesson board stays phone-sized in the
  middle of a large screen.
- Board chrome states size **then** difficulty ("Medium · Hard"), matching the
  Daily card and Stats, and shows the *requested* band, matching records.
- Persistence invariants (inherited, pinned by tests): save on board change +
  scene backgrounding + disappear, never phase-change-only; `savedGame` is
  observable state; `ResumeGameView` resolves its snapshot once on appear.
- Solves are filed under the **requested** difficulty; background = paused
  (wall-clock tick).
- Win: connectivity ripple (BFS hop stagger from the last bridge) → win card
  with the hanko seal → technique recap. Ripple haptics capped at 3 hops.

## Daily & streaks

`DailySeed`: FNV-1a over `"hashi.daily.v1.YYYY-MM-DD"`; weekday schedule via
Zeller (calendar-independent). **The seed string, the schedule, and the RNG
stream are shipped API** — changing any of them changes every player's daily.
Streak record keyed by ISO day strings; `displayStreak`/`streakIsAtRisk` are
computed, never stored (stored values go stale at midnight); replaying an older
day never rewinds `lastCompleted`.

**The Daily is exempt from the board-size gate.** The schedule puts a `.large`
board on Saturday and Sunday, `.large` is behind the unlock, and the Daily is
free. The schedule cannot move — it is shipped API — so the gate bends instead:
`FeatureGate.isDailyAvailable` is a separate function returning `true`, so the
exemption reads as policy rather than as a special case buried inside
`isSizeAvailable`. It is also the best funnel the app has, which is what
`shouldOfferUnlock(afterSolving:wasDaily:unlocked:)` and the win-card offer are
for. `theDailyIsFreeAtEverySizeItSchedules` counts the large days it walked and
fails if there are none, so the test cannot go vacuous if the schedule changes.

## Simulator driving

Same fb-idb setup as Kakuro (`../../studio/idb-venv`). Drive from a single Python
process; find elements via the accessibility tree (islands expose
"Island N, row R, column C" + bridge-count values); read the app's own save
(`hashi.saveGame.v1` via plistlib+json) to learn a live board's solution.
The save only exists after a board change or backgrounding.

## Project configuration

Bundle `de.kaikunze.hashi`, display name "Just Hashi", team `8H42EZRCCP`,
iOS 18.0+, iPhone + iPad, portrait on iPhone, all orientations on iPad.
App Store Connect app id **6799235188**, SKU **3466**, IAP id **6799257985**.

The ASC record began life as "MathMaze" on `de.kaikunze.mathmaze`; on
2026-08-08 it was repointed to `de.kaikunze.hashi` (registered bundle id
`7NGR8TL25S`) before any build was uploaded. **That window has closed: the
bundle ID is now locked forever.** The record also carries four platform
versions (iOS, macOS, tvOS, visionOS) though only iOS ships, so **every
AppShip call must pass `--platform IOS`** or the copy lands on the macOS
version. Full runbook: `AppStore/SUBMISSION.md`.
Privacy manifest: UserDefaults / CA92.1 — key name is
`NSPrivacyAccessedAPITypeReasons` (misspelling it cost Kakuro two rejected
builds; `ReleaseBuildTests` pins the exact names). The app icon is generated by
`tools/icon/generate_appicon.py` — outside `Hashi/` for the same reason as the
StoreKit config; render 4× and downsample, and save RGB with **no alpha**
(alpha in App Store artwork is rejected under ITMS-90717).

## The one-time unlock

One non-consumable, `de.kaikunze.hashi.full`, $4.99, family-shareable. No ads,
no subscription. Ported from Kakuro's `Store/`, which is where most of these
lessons were paid for.

**Free:** small + medium boards at every difficulty · the rules lesson, Full
Islands and Only Neighbor · the "something here is wrong" error hint · the
Daily puzzle and its streak · the mastery tracker keeps recording silently.
**Paid:** large boards · the six remaining lessons · all practice drills ·
mastery *display* · the escalating hint ladder · Stats.

- **All gating lives in `FeatureGate`**, as pure `nonisolated` functions taking
  `unlocked:` explicitly — no StoreKit, no isolation, so the rules are testable
  without a store. `freeLessonsAreExactlyTheFirstTwo` builds the free set by
  filtering the whole universe and compares it to a literal, so adding a
  technique without deciding its tier fails a test rather than shipping.
- **`Transaction.currentEntitlements` is authoritative; `hashi.entitlement.v1`
  is a display hint** so the first frame after a cold launch doesn't show locks
  to somebody who paid. `EntitlementSource.isOwned` returns `Bool?` — **`nil`
  means "couldn't determine" and must never downgrade**, or offline players
  lose what they bought. `productionSourceCanReportIndeterminate` scans the
  shipping source for a `nil` path; without it that contract is dead code on a
  device and its unit test only exercises the stub, which is what shipped in
  Kakuro build 1.
- The `Transaction.updates` listener starts in `EntitlementStore.init`, not a
  view's `.task` — it has to be live before any transaction completes, and it
  is what delivers an Ask to Buy approved later. `ListenerBox` exists because a
  `@MainActor` deinit is nonisolated and cannot cancel isolated state.
- **Gate the mastery display, not `MasteryTracker`.** It keeps recording for
  free players; showing an empty progress path to someone who just paid would
  punish the purchase.
- **Withholding a hint must not call `mastery.recordHint`** — that would damage
  the progress path for a hint they never saw. The withheld copy also names no
  technique. Unlike Kakuro, Hashi flags the *free error hint* locked too, so
  its banner offers "Unlock hints" instead of a "Tell me more" that escalates
  to the same hint and visibly does nothing.
- **Paywalled rows stay tappable** (they present the paywall); only
  mastery-locked rows are `.disabled`. A dead row neither teaches nor sells.
- The size picker **snaps back** rather than hiding the Large segment — a
  hidden feature can't be sold — and returns before `cache.warm`, because
  building a large board costs real CPU for a puzzle they can't open.
- **Stats is panel-gated, not screen-gated** (divergence from Kakuro): its
  daily streak is free-tier data, so locking the whole screen would hide
  something the player owns.
- The win-card → paywall handoff needs an `onDismiss` hop. The paywall sheet is
  rooted on the NavigationStack, so setting its context while the win sheet is
  up presents nothing.
- Simulator testing: `StoreKit/Hashi.storekit`, wired via the **shared** scheme
  (`<StoreKitConfigurationFileReference>`). Keep the config outside `Hashi/` —
  the synchronized root group would otherwise ship it inside the app bundle.
  The scheme's `<TestAction>` must not contain an empty `<TestPlans>` element;
  that makes xcodebuild report "not configured for the test action".
  `schemeWiresTheStoreKitConfigAndKeepsTestActionClean` pins both.
- `simctl launch` does **not** apply a StoreKit configuration — that binding
  lives in the scheme's Launch action and is applied by Xcode. Run once from
  Xcode to exercise real purchase/restore flows.
- Screenshots of the paid tier need `-HashiScreenshotUnlock`, wrapped in
  `#if DEBUG` so it cannot exist in a shipped build. The constant sits outside
  the `#if` (the test has to name it); only the use is guarded.
- **The first in-app purchase must ride along with a version submission.**
  Kakuro's visionOS 1.0 was rejected under Guideline 2.1(b) because the IAP was
  configured but never attached to a review submission.
