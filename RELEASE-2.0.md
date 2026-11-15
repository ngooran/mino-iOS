# Mino 2.0 Release Guide

Everything about the 2.0 release in one place: what changed, what is done, and the steps left, in order.

Status on 15 Nov 2026: the code is done on branch `redesign-2.0` (pushed, not merged), the Mino Pro in-app purchase exists in App Store Connect, and raw screenshots are taken. Nothing has been submitted to Apple yet.

---

## 1. What 2.0 Is

| | 1.2 (live) | 2.0 |
|---|---|---|
| Business model | Paid app, €2.99 | Free download + **Mino Pro**, a one-time €4.99 purchase |
| Free tier | Everything | 3 single-file compressions a day, with the Smallest, Balanced and Best Quality presets |
| Pro | n/a | Unlimited compressions, batch compression, merge, split, custom quality and resolution |
| People who paid for 1.x | n/a | Keep everything. Pro is unlocked automatically (see "Grandfathering" below). |
| Design | Custom theme, always dark | System-standard SwiftUI: light and dark mode, Liquid Glass on iOS 26 (bordered fallbacks on iOS 18.6+) |
| iPad | Supported | Redesigned: sidebar + two-column layout |
| iPhone Duo | Not supported | Closed: iPhone layout. Open: two columns. Book pose: the columns meet at the hinge, and the paywall splits across the two pages. |
| Version | 1.2 (3) | 2.0 (4) |

Code-level details are in [CLAUDE.md](CLAUDE.md). App Store texts are in [AppStoreMetadata.md](AppStoreMetadata.md).

### Grandfathering 1.x buyers

`ProStore.checkLegacyPurchase()` reads `AppTransaction.originalAppVersion`, which is the *build number* the person first got. Pro unlocks when that number is below `firstFreemiumBuild` (4).
- Paid builds were 1 and 3, so 2.0 must ship as build 4 or higher, and the threshold must never be raised.
- Only production receipts count. In TestFlight and the sandbox, the original version is always "1.0", so this path can't be tested before release. The fallback is "Restore Purchase", which won't help a 1.x buyer either. Watch support mail after launch.

---

## 2. Done

### Code (branch `redesign-2.0`)
- [x] Redesign: Home / Files / Settings tabs, the task flows (Compress, Merge, Split), the Files list with a preview, Statistics, and the Mino Pro paywall
- [x] Adaptive layout for iPhone, iPad and iPhone Duo (closed, open flat, book pose)
- [x] StoreKit 2 purchase, restore and entitlement checks; free daily limit; grandfathering
- [x] Size estimate per quality preset; output files keep readable names
- [x] Version 2.0, build 4, for all targets
- [x] Local StoreKit test file `Mino.storekit` (€4.99), wired into the shared `Mino` scheme
- [x] DEBUG-only screenshot sandbox and demo launch arguments (not in Release builds)

### App Store Connect
- [x] In-app purchase **Mino Pro** created, Apple ID `6835189769`, product ID `com.applestan.Mino.pro`
  - Non-consumable, €4.99, with the Netherlands as base territory (proceeds about €3.51)
  - Available in all 175 territories, and in new ones automatically
  - Family Sharing on (permanent)
  - en-US display name and description set; reviewer screenshot uploaded
  - State: **Ready to Submit**

### Assets
- [x] Raw en-US screenshots in `Screenshots/raw/en-US/`, 7 screens per device (`01-home` ... `07-paywall`):

| Folder | Device | Size | App Store Connect slot |
|---|---|---|---|
| `iphone-6.9/` | iPhone 18 Pro Max | 1320×2868 | iPhone 6.9" (required) |
| `ipad-13/` | iPad Pro 13" | 2064×2752 | iPad 13" (required for iPad apps) |
| `iphone-duo/` | iPhone Duo, open flat | 2853×2007 | iPhone Duo |
| `iphone-duo-closed/` | iPhone Duo, closed | 1398×2034 | iPhone Duo (alternative size) |

---

## 3. Next Steps, in Order

Every step that touches App Store Connect is outward-facing. Do it deliberately, one step at a time.

### Step 1: Decide the open questions
- [x] **Free limit:** 3 a day (`FreeUsage.dailyLimit`), confirmed on 15 Nov 2026 as part of the roadmap's free/Pro split. The price stays €4.99.
- [ ] **Localizations:** ship 2.0 in English only, or add the languages planned in AppStoreMetadata.md (de-DE, es-ES, fr-FR, pt-BR)? The app has no string catalog yet, so translation is a separate project. Recommendation: ship 2.0 in English and localize in 2.1.

### Step 2: Test on real hardware with TestFlight
1. Archive a Release build and upload it, either with Xcode Organizer or with:
   ```bash
   xcodebuild -project Mino.xcodeproj -scheme Mino -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/Mino.xcarchive archive \
     -allowProvisioningUpdates -authenticationKeyPath <AuthKey.p8> \
     -authenticationKeyID 9CZTDH7H5U -authenticationKeyIssuerID <issuer>
   ```
   Then export an `.ipa` with `-exportArchive` and upload it with `asc builds upload` (see `asc builds upload --help`). A Release build for the *simulator* fails because the MuPDF frameworks are arm64-only, which is expected. The device build works.
2. Install it from TestFlight and check, with a sandbox Apple Account:
   - [ ] Fresh install shows "3 free compressions left today"; the 4th compression opens the paywall
   - [ ] Merge, Split, batch and Custom open the paywall when not Pro
   - [ ] Purchase works and unlocks everything at once, then continues the action that was blocked
   - [ ] Restore Purchase works after deleting and reinstalling the app
   - [ ] The paywall shows the real price (it is fetched from the App Store)
   - [ ] Share Extension: share a PDF from Files or Mail into Mino
   - [ ] Open a PDF with Mino from the Files app ("Open in")
   - [ ] iPad: drag a PDF in from another app in Split View
   - [ ] iOS 18 device, if available: the bordered button fallbacks look right (only iOS 26+ was tested)
   - [ ] iPhone Duo hardware, only if you choose to test on it: book pose, flat and closed
3. Fix anything found, and bump the build number (5, 6, ...) for each new upload. Never go below 4.

### Step 3: Finish the screenshots
- [ ] Turn the raw shots into marketing images: device frame (optional) and a caption on each, which gets 25-30% better conversion (see "Screenshot Recommendations" in AppStoreMetadata.md). `asc screenshots frame` can add device frames.
- [ ] Pick the order. Suggested: Home → Compress (size estimates) → Result (75% smaller) → Merge → Split → Files. Leave the paywall out of the store screenshots.
- [ ] Retake raw shots if the UI changes. The workflow is in CLAUDE.md under "App Store Screenshots": simulators only, `-demoSandbox`, 9:41 status bar, `hinge` for the Duo.
- [ ] Known cosmetic issue: on short screens (the open Duo, the closed Duo) the Result screen's last row ("Compress Another") sits partly behind the Share button. Either fix the layout or crop around it.

### Step 4: Prepare version 2.0 in App Store Connect
- [ ] Create version 2.0 (iOS) and attach the TestFlight build.
- [ ] Paste the texts from AppStoreMetadata.md: What's New 2.0, Promotional Text, Description. Keywords and subtitle can stay.
- [ ] Upload the screenshots for iPhone 6.9", iPad 13" and iPhone Duo.
- [ ] Under **In-App Purchases and Subscriptions** on the version page, add **Mino Pro**. An app's first in-app purchase can only be submitted together with an app version.
- [ ] App Review notes: paste "Notes for App Review (2.0)" from AppStoreMetadata.md.
- [ ] App Privacy: no change needed. StoreKit purchases go through Apple, and Mino still collects no data.
- [ ] Set the release option to **Manually release this version**, so the release and the price change can be timed together (step 6).

### Step 5: Submit for review
- [ ] Submit version 2.0 with Mino Pro attached.

### Step 6: Release, and make the app free
Order matters, because grandfathering keys on the build number:
- Anyone who downloads **1.2** gets build 3 and therefore free Pro forever.
- Anyone who buys **2.0** while it still costs €2.99 gets build 4 and does *not* get Pro, even though they paid.

So the app must not be free while 1.2 is the live version, and 2.0 must not be sold for €2.99.

Recommended sequence, once 2.0 is approved (it waits as "Pending Developer Release"):
1. Change the app price to **Free**, starting today, with the Netherlands as base territory.
2. Immediately press **Release This Version** on 2.0.

The short window between the two can only give a few people free Pro, which is harmless. Doing it the other way round would charge people for an app without Pro. Never make the app free before 2.0 is approved.

### Step 7: After launch
- [ ] Merge `redesign-2.0` into `main` and tag `v2.0`.
- [ ] Watch for 1.x buyers saying Pro didn't unlock (the grandfathering path can't be tested before release).
- [ ] Check conversion in App Store Connect analytics: downloads before and after, and Pro purchase rate. Then reconsider the free limit and price.
- [ ] Start 2.1 from [ROADMAP.md](ROADMAP.md): 10 new tools in four releases (2.1–2.4), with the free/Pro split, price path and App Store plan.

---

## 4. Reference

| Item | Value |
|---|---|
| App Store app ID | 6757166913 |
| Bundle ID | com.applestan.Mino |
| Mino Pro | Apple ID 6835189769, product ID `com.applestan.Mino.pro` |
| Current live version | 1.2 (build 3), €2.99 |
| 2.0 build | 4 (minimum, never lower) |
| Deployment target | iOS 18.6 (app and Share Extension) |
| Xcode | 27.2. Xcode 27.1+ is needed for iPhone Duo. |
| ASC API key | Key ID `9CZTDH7H5U`, stored for the `asc` CLI (profile "ComicFlow", covers all team apps) |

### Useful commands
```bash
# Mino Pro status
asc iap view --id 6835189769

# App price and availability
asc pricing current --app 6757166913

# Open any screen with sample data (DEBUG build, simulator)
xcrun simctl launch <udid> com.applestan.Mino -demoSandbox -demoAppearance light -demoScreen paywall -demoFree

# Fold the iPhone Duo simulator
hinge open | hinge close | hinge 110 | hinge screenshot out.png
```

### Testing purchases locally
Run the `Mino` scheme from Xcode. It uses `Mino.storekit`, so purchases work without App Store Connect. DEBUG builds also have a Pro/Free switch and a "Reset Free Compressions" button in Settings.
