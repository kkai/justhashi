# Accessibility audit — Just Hashi

This audit and its fixes are on branch `a11y-audit`, 2026-10-03. Tag
`pre-a11y-audit` marks `main` before the work. Nothing here has been
uploaded. The method is the one in `../shikaku/docs/ACCESSIBILITY.md`:
- common tasks
- `performAccessibilityAudit` per screen
- WCAG ratios computed from `Design/Theme.swift`
- Dynamic Type at AX5
- a code review for motion, targets and announcements

Hashi ships on iPhone and iPad.

## Findings

🔴 blocks a common task · 🟠 puts a feature claim at risk · 🟡 friction · 🟢 polish

| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | 🔴 | **Bridges could only be drawn by dragging or by tapping the water between islands.** Islands were well-labelled elements, but they had no actions, and the corridors aren't elements. A puzzle couldn't be solved with VoiceOver, Switch Control or Voice Control. | **Fixed.** Each island has one action per corridor, named for what it does: "Add a bridge to the 4 on the right", "Make the bridge … double", "Remove the bridges …". Each action goes through `onCycleEdge`, so a lesson can still refuse it. The island's value lists its corridors ("1 bridge to the 4 on the right, no bridge to the 2 below"). `Game/BoardSpeech.swift`, `BoardView.swift`. |
| 2 | 🔴 | Nothing was announced: bridge moves, finished islands, hints, the win. | **Fixed.** Each action says what it did ("Double bridge between the 3 at row 2, column 4 and …. The 3 is complete"). Hints are announced on every rung, and the win with its time and record. |
| 3 | 🟠 | Hint text points at highlighted islands without positions. | **Fixed.** `BoardSpeech.spokenHint` names up to four highlighted islands and, at the last rung, the bridges with their counts. |
| 4 | 🟠 | Contrast failures. Light: `inkSoft` 3.7–3.8, vermillion text on the sea 3.8. Dark: text on filled buttons 2.0, an overfilled numeral on its island 3.4. | **Fixed.** `inkSoft` light alpha 0.70 (5.8). Light vermillion darkened (5.0). New tokens `onBridge` (dark text on the pale dark-mode bridge, 7.1) and `vermillionOnIsland` (4.8 or more). |
| 5 | 🟠 | The finished-island ring (`foam`, on the disc) was 2.2–2.8:1, so a finished island lost its ring. | **Fixed.** `foamOnIsland`, 3.9:1 or more. The ring is also a full circle, which is a shape cue as well as colour. |
| 6 | 🟠 | Targets under 44 pt: the hint ✕ (about 20), the sheet close (about 33), the banner buttons (about 36). | **Fixed.** All 44 pt or more. |
| 7 | 🟠 | Fixed font sizes: the timer, the win time, Stats, Home counters and icons. | **Fixed.** `.numberFont(_:)` / `.scaledFont` (`Design/ScaledType.swift`, `@ScaledMetric`). |
| 8 | 🟡 | Reduce Motion: the hint banner slid in, and the rejected-bridge wiggle ran regardless. | **Fixed.** The banner fades in and the wiggle is skipped. The entrance, settle, ripple and stamp were already gated. |
| 9 | 🟠 | The audit found more contrast failures. Learn and Practice rows were faded to 60%, including paywalled rows that stay tappable. The small "JUST" in the wordmark failed over the sea, and the Settings section headers and footers, in the system grey, only nearly passed. | **Fixed.** No fade; locked rows keep their lock glyph. "JUST" and the headers in ink, the footers in `inkSoft`. |
| 10 | 🟡 | Times were spoken as clock times ("Time 4:07", "completed in 4:07"). | **Fixed.** `TimeFormatting.spoken`: "4 minutes 7 seconds". |

### Accepted, with reasons

- **Island numerals and the wordmark** are drawings sized to their disc and
  logotype. They are filtered in the audit by label. VoiceOver reads each
  island in full.
- **Islands under 44 pt** on large boards. The board fills the space, and the
  island actions don't depend on touch size.
- **System List screens** (Learn, Stats, Settings): Dynamic Type and clipping
  reports on standard rows are filtered on those screens only.
- **Unattributed Dynamic Type reports with the hint banner up**, as in
  Kakuro. These are filtered on the hint screen only.

### Strengths (kept)

- Islands were already elements with 1-based positions and a value.
- The win stamp, settle and ripple already honoured Reduce Motion.
- Learn rows carry their state, and their badges are hidden.

## Tests

- `HashiTests/BoardSpeechTests.swift`: action names through a full cycle,
  move announcements, sides, spoken times.
- `HashiUITests/AccessibilityAuditTests.swift`: one audit per screen
  (Home, board, hint, Learn, Stats, Settings, Home at AX5), launched with
  `-uiTestResetState -HashiScreenshotUnlock`. Both flags are DEBUG only.

## Result

`xcodebuild test` (iPhone 16 Pro, iOS 18.5), 2026-10-03:
- All 7 audit screens pass with the filters above.
- 158 unit tests pass in unit-only runs, twice on this branch.
- In the full serial run (`-parallel-testing-enabled NO`, UI tests included),
  `PuzzleCacheTests.requestAfterWarmAwaitsTheSameGeneration` failed twice: it
  counted two generations instead of one. The test races a warm against a
  request and touches no code changed here, but this is an observation, not
  a proof. Look at it before release.

## Accessibility Nutrition Labels

These become claimable once this branch ships:
- VoiceOver
- Voice Control (island actions under "Show actions")
- Larger Text (with the numeral exception)
- Sufficient Contrast
- Dark Interface
- Differentiate Without Color Alone
- Reduced Motion
