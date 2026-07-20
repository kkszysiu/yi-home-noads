# Yi Home — Ad Removal Notes

How the ad-free patch works, and how to fix it when a new app version brings ads
back. Written against **Yi Home 6.9.2** (`versionName 6.9.2_20260522071155`).

## Pipeline (unchanged)

`.github/workflows/patch-apk.yml` runs on every push that touches the `.xapk`,
`scripts/**`, or the workflow itself:

1. Merge the split XAPK into one APK — `APKEditor m`
2. Decode to smali — `APKEditor d`
3. Apply `scripts/patch-ads.sh decoded`
4. Rebuild — `APKEditor b`
5. Sign — `uber-apk-signer`
6. Publish a GitHub release tagged `v<version>-noads`

To reproduce locally you need `APKEditor.jar` and a JDK. Same three commands
(`m` / `d` / `b`), then run the patch script against the `decoded/` directory.

## Why ads came back in 6.9.2

The old script matched **obfuscated method names** (`r2`, `s2`, `G2`, `l0`, …).
Obfuscated names are reassigned on every rebuild, so in 6.9.2 those patches
either missed or — worse — hit the *wrong* method. Concretely:

- `SplashActivity.r2()` in 6.9.2 is just splash **UI setup**, not the ad loader.
- `SplashActivity.y2()` is now itself a **yd.saas splash-ad loader**. The old
  script rewrote other methods to *call* `y2()`, i.e. it actively triggered an ad.
- `NativeAdvertisingGoogleAdUtil` (the in-app banner/native util) was renamed by
  the obfuscator to `oc/n1`, so the filename-based lookup found nothing and that
  entire surface went unpatched.

6.9.2 also swapped a single Google ad path for a large mediation stack: TradPlus,
Vlion, Moloco, Vungle, Fyber, Brandio, yd.saas, secmtp, plus AdMob.

**Lesson:** anchor patches on *stable* things — Kotlin `.source` filenames and
semantic chokepoints — not on obfuscated class/method letters. When a patch can't
find its target, fail the build loudly instead of shipping ads silently.

## Ad surfaces in 6.9.2 and how each is disabled

Locate classes by their `.source` line (survives renames), not by class letter:
`grep -rl '\.source "<Name>.kt"' smali/`.

### 1. Splash ads — `SplashActivity.L2()`
`L2()` is the orchestrator. It fetches the server ad config (`BannerDetailBean`
via `h2()`) and dispatches by `category`:
`0x30`→`y2()` yd.saas, `0x31`→`q2()` Google, `0x35`→`w2()` secmtp/TopOn,
`0x44`→`x2()` TradPlus, else→`M2()` Yi self-promo. When **no** ad is configured it
runs its own no-ad path: `K2(true)` (show Yi logo, hide skip) then `O2()`
(`P2(getIntent())`, route into the app).

**Patch:** replace the whole `L2()` body with exactly that no-ad path
(`K2(true)` + `O2()`). One edit kills every splash network, regardless of which
one the server picks.

### 2. In-app banner / native ads — `pb/o.a()` (`UnderViewManager.kt`)
The renamed util `oc/n1` renders banners/natives into a `FrameLayout` via
`M/N/Q/R/S(FrameLayout)V` and loaders `X/k0/l0(...)`. Every one of these gates on
`pb/o.a()Z` first: **when `a()` returns true the method returns early and no ad is
shown** (it's the app's own audit/premium suppression check). Referenced 18× in
`oc/n1`. Placements: device list, camera player, alert video, alerts list, user
profile.

**Patch:** force `pb/o.a()` to `return true`. One edit disables all in-app
native/banner placements through the app's own gate.

### 3. App-open / interstitial / resume ads — `l0` (`GoogleAdManager.kt`)
Methods: `n(Activity,Z)` / `v(Activity,Z)` dispatch and fire the completion
callback `l0$b.e(Z)`; `s(Activity)` / `t(Activity,I)` load+show AppOpen/Interstitial;
`o()Z` shows the app-open ad on **resume** (called from
`AntsApplication$b.onActivityStarted`); `r()Z` reports "ad ready".

**Patch:** `s`/`t`→`return-void`; `n`/`v`→immediately call `l0$b.e(true)` then return
(so any waiting caller proceeds); `o()`→`return false`; `r()`→`return false`.
Neutering `o()` kills resume ads without touching session-tracking code, so we do
**not** need to nuke `onActivityStarted` anymore.

### 4. Cloud / AI upsell popups (best-effort)
Subscription nags, treated as ads. All base classes verified:
- `FreeCloudDialogFragment` (extends `DialogFragment`) → `dismiss()` in `onViewCreated`
- `SmartAIPurchaseDialog` (extends `DialogFragment`) → `dismiss()` in `onCreate`
- `CloudIntroductionsActivity`, `NoCloudIntroductionsActivity`,
  `CloudFeaturesActivity`, `AdDialogFragment` (all extend `BaseActivity`) →
  `finish()` right after `super.onCreate`

These are best-effort: a miss warns but does not fail the build.

## Playbook for the next version bump

1. Drop the new `.xapk` in the repo root (replace the old one).
2. Decode locally and re-verify each anchor still holds:
   - `SplashActivity.L2()` still the splash orchestrator; `K2(Z)`/`O2()` still the
     no-ad path.
   - `pb/o` still `UnderViewManager.kt`; `a()` still the early-return gate in the
     display methods (check `if-eqz` after `Lpb/o;->a()Z`).
   - `l0` still `GoogleAdManager.kt`; `n/s/t/v/o/r` signatures unchanged;
     `l0$b.e(Z)V` still exists.
3. Adjust `scripts/patch-ads.sh` only where an anchor moved.
4. Push; the workflow builds and releases. If a **core** patch fails to match, the
   script exits non-zero — fix it before shipping.
