# Just Hashi — App Store submission runbook

State as of 2026-08-08: everything is prepared and in App Store Connect, on build 2. The
version sits in `PREPARE_FOR_SUBMISSION`. **Two things are left, both yours,
and they are in §1.**

## App record facts (matter for every future release)

- ASC App ID **6799235188** · SKU **3466** · bundle `de.kaikunze.hashi` · team `8H42EZRCCP`
- The record was a reused **MathMaze** shell on `de.kaikunze.mathmaze`. It was
  repointed to `de.kaikunze.hashi` (registered bundle id `7NGR8TL25S`) on
  2026-08-08, before any build was uploaded. **That window is now closed: the
  first build has landed, so the bundle ID is locked forever.**
- The record carries **four platform versions** (iOS, macOS, tvOS, visionOS),
  all 1.0. Only iOS ships. **Always pass `--platform IOS` to AppShip** — its
  version lookup takes the first version returned, which on a record like this
  is the macOS one, and metadata would land silently on the wrong platform.
- iOS 1.0 version id `0434786c-eefe-4922-82cc-20e4af5b8c82`,
  en-US localization `5a7a0c5d-69a2-48c1-b505-fb870c1647ca`,
  appInfo `5cec6feb-4929-4827-a939-fda8e31126bb`,
  appInfoLocalization `20b119e2-f7f7-45f3-ab54-980015b13a07`.
- IAP `de.kaikunze.hashi.full`, ASC id **6799257985**, $4.99, family-shareable.
- `whatsNew` is deliberately empty: it returns 409 on a first version.

## 1. What is left

- [ ] **App Privacy → "Data Not Collected".** The only field with no public
      API. It is the only answer consistent with `PrivacyInfo.xcprivacy`
      (UserDefaults / CA92.1) and with the published privacy policy; any other
      answer contradicts both.
- [ ] **Press "Add for Review" / Submit.**

## 2. The thing that cost Just Kakuro a rejection

**The IAP must be an item in the review submission, not merely configured.**

`de.kaikunze.hashi.full` is in `READY_TO_SUBMIT`, which means configured and
attached to nothing. Just Kakuro's visionOS 1.0 was rejected under **Guideline
2.1(b)** in exactly this state, with price, localization, promotional image and
review screenshot all already `COMPLETE`. An in-app purchase is not reviewed
because it exists; it is reviewed because it is an item in a review submission
alongside the app version.

In the ASC UI this is the **"In-App Purchases and Subscriptions"** section on
the 1.0 version page: add `Just Hashi Full` there before submitting. If you do
it through the API instead, the relationship on `reviewSubmissionItems` is
`inAppPurchaseVersion`, pointing at an `inAppPurchaseVersions` id — not
`inAppPurchaseV2`, not the IAP id. It does not appear in the valid `include`
list, so it cannot be discovered by probing. `POST /v1/inAppPurchaseSubmissions`
is **not** the answer for a first submission; it returns "no pending version
for submission" even when one exists.

Recovery if it is submitted without the IAP: cancel with `PATCH {canceled:
true}`. ASC then creates a replacement submission that already contains the IAP
version, which is why re-adding it returns `RELATIONSHIP.INVALID.NOT_ALLOWED`.
Add the app version to that new submission and submit it.

## 3. What is already done

| | |
|---|---|
| Build | 1.0 (2), `VALID`, attached to the iOS 1.0 version. Build 1 was superseded by the swipe-back fix, the play field redesign and the copy pass |
| Screenshots | 6 iPhone 6.5" + 6 iPad 12.9", every asset `COMPLETE` |
| Description / promo / keywords | 1985 / 164 / 96 characters, all within limits |
| Subtitle | `Learn to build the bridges` (26 of 30) |
| Support + marketing URL | `https://kaikunze.de/justhashi/`, both live and 200 |
| Category | Games, subcategories Puzzle and Board |
| Age rating | every question none/false → 4+ |
| Copyright | `2026 Kai Kunze` |
| Price | Free, base territory USA |
| IAP | `READY_TO_SUBMIT`, $4.99, family-shareable, all 175 territories, promo image `PREPARE_FOR_SUBMISSION`, review screenshot `COMPLETE` |
| App Review contact | Kai Kunze, kai.kunze@gmail.com, +4972544577, no demo account needed |
| App Review notes | `metadata/review-notes.txt`, 1416 characters |
| Export compliance | answered by `ITSAppUsesNonExemptEncryption = NO` in the build |
| Real-device check | Release build installed and launched on Zelos (iPhone 12 Pro Max) |

## 4. Regenerating any of it

```bash
# Screenshots (iPhone 11 Pro Max + iPad Pro 12.9" 6th gen, 9:41 status bar)
python3 AppStore/capture_screenshots.py

# IAP promotional image
python3 AppStore/iap/generate.py

# App icon
python3 tools/icon/generate_appicon.py

# Metadata and screenshots to ASC (--platform IOS is not optional here)
cd ../appstoreconnect/appship
.build/release/AppShip metadata --bundle-id de.kaikunze.hashi \
  --create-version 1.0 --locale en-US --platform IOS \
  --description-file … --promo-file … --keywords-file …
.build/release/AppShip screenshots --bundle-id de.kaikunze.hashi \
  --create-version 1.0 --locale en-US --platform IOS \
  --iphone-dir … --ipad-dir … --replace
```

**Verify uploads through the API, not the tool's exit code.** AppShip has
reported success on a rejected upload before. Screenshots carry
`assetDeliveryState`; IAP images carry `state`, where `PREPARE_FOR_SUBMISSION`
is healthy.

## 5. Build and upload

```bash
xcodebuild archive -project Hashi.xcodeproj -scheme Hashi -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/JustHashi.xcarchive \
  -allowProvisioningUpdates -authenticationKeyPath <p8> \
  -authenticationKeyID <KEY_ID> -authenticationKeyIssuerID <issuer>
xcodebuild -exportArchive -archivePath build/JustHashi.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates …
xcrun altool --validate-app -f build/export/Hashi.ipa -t ios --apiKey … --apiIssuer …
xcrun altool --upload-app   -f build/export/Hashi.ipa -t ios --apiKey … --apiIssuer …
```

The archive signs with the *development* identity; distribution signing happens
at export. Passing the API key to both steps is what lets Xcode mint an App
Store profile and use a Cloud Managed distribution certificate — there is no
distribution certificate in this machine's keychain.

Always `--validate-app` first: it catches icon, version and entitlement
problems without consuming an upload.

`CURRENT_PROJECT_VERSION` is the build number and must increase for every
upload against the same `MARKETING_VERSION`. It is `2`.

Check the exported `.ipa` before uploading: no `.storekit` fixture, no
`*.debug.dylib` or `__preview.dylib`, `PrivacyInfo.xcprivacy` present,
`ITSAppUsesNonExemptEncryption` false, and `strings` clean of
`HashiScreenshotUnlock`.

## 6. Traps specific to this app

- **The privacy manifest key is `NSPrivacyAccessedAPITypeReasons`.** Just
  Kakuro lost two builds to ITMS-91056 over the missing word "Type". Nothing
  local catches it: `plutil -lint` and `altool` both pass on the wrong key, and
  Apple's validator reports by email only, about an hour per round trip.
  `ReleaseBuildTests.privacyManifestUsesApplesKeyNames` pins the spelling
  against key names written out by hand from Apple's documentation.
- **App Store artwork must have no alpha** (ITMS-90717). The icon and IAP
  generators both save RGB; the screenshot driver flattens.
- **`APP_IPHONE_67` uploads never display in ASC** despite the API accepting
  them. The set here is `APP_IPHONE_65` (1242×2688) plus
  `APP_IPAD_PRO_3GEN_129` (2048×2732).
- **The IAP description caps at 55 characters**, shorter than the page implies.
  Ours is 53.
- **The IAP review screenshot must be 2048×2732.** A 6.9" iPhone capture is
  refused with "the dimensions of one or more screenshots are wrong".
- The review contact **phone needs `+countrycode` format**, and a version
  cloned from a previous one already has a review detail, so it must be PATCHed
  rather than POSTed.
