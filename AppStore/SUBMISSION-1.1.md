# Just Hashi 1.1: submission runbook

State on 2026-10-20: **built and tested locally on branch `release-1.1`, nothing
in App Store Connect yet.** Nothing is merged to `main`, pushed, uploaded or
submitted. `AppStore/SUBMISSION.md` still holds the record facts and the
traps; read it first.

## What 1.1 is

- **Accessibility pass** (the `a11y-audit` branch, 2026-10-03, now included):
  VoiceOver island and bridge actions, spoken moves, hints and win, contrast
  tokens, 44pt targets, Dynamic Type, Reduce Motion. `docs/ACCESSIBILITY.md`
  has the findings and the Nutrition Label claims.
- **Streak fix.** Finishing an older saved Daily after a newer one used to
  reset the streak to 1. Ported from Kakuro 1.1; the test now checks the streak,
  not only `lastCompleted`.
- **Share card.** The win card of a Daily has a Share button: an image of the
  island silhouette (no clues, no bridges), date, time and streak, plus a text
  line. `Hashi/Game/DailyShare.swift`.
- **Past dailies.** A Home row lists every Daily since 2026-08-08 (capped at a
  year) with your times. Opening one is a new `PaidFeature.dailyArchive`;
  locked rows present the paywall. Today's Daily stays free. The paywall's
  feature list grows by one row automatically (`PaidFeature.allCases`).
- **More Just Puzzles.** A Settings section with plain App Store links to
  Kakuro, Shikaku, Nurikabe and Numeriqo.
- Test fix: `requestAfterWarmAwaitsTheSameGeneration` and `dailyKeyIsCacheable`
  (`PuzzleCacheTests`) raced the re-warm that `settle` starts; they now count
  generations started before the first one finished. The cache suite then
  passed 50 iterations in a row.

The daily schedule and seed are untouched (shipped API).

## Left for Kai

- [ ] Look at the share card and the Past dailies screen on a device.
- [ ] Merge `release-1.1` into `main`, push to kkai/justhashi.
- [ ] Create the iOS 1.1 version in ASC; What's New from
      `metadata/whatsnew-1.1.txt`.
- [ ] The IAP display description and `metadata/description.txt` list what the
      unlock buys; add past dailies (the IAP description caps at 55 characters).
- [ ] Review notes: past dailies are paid, today's Daily free; the share image
      is generated on device, nothing is uploaded.
- [ ] New screenshots only if wanted: Home gained one row.
- [ ] Build 1.1 (3), upload and attach, following `SUBMISSION.md` §5.

## Not in 1.1, on purpose

- **macOS, tvOS, visionOS.** The ASC record carries prepared 1.0 versions, but
  the Hashi target builds for iOS only (`SUPPORTED_PLATFORMS = iphoneos
  iphonesimulator`). Shipping them is a port like Kakuro's, not a submission.
- **Widget** (today's Daily + streak). Needs a widget extension target and an
  App Group so the extension can read `ProgressStore`; the App Group has to be
  registered on the developer account first.
- **Harder weekend dailies.** The schedule is shipped API (`docs/ENGINEERING.md`
  § Daily & streaks); changing it changes every player's daily.
