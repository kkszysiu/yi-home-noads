# Yi Home — No Ads

Automated patcher that removes ads and subscription upsell popups from the
**Yi Home** Android app (`com.ants360.yicamera.international`), then rebuilds and
signs an installable APK.

Drop a new app package in the repo, push, and GitHub Actions publishes an ad-free
release.

## How it works

`.github/workflows/patch-apk.yml` runs on every push that touches the app package
(`*.xapk` / `*.apk`), `scripts/**`, or the workflow itself:

1. **Merge** the split XAPK into a single APK — [APKEditor](https://github.com/REAndroid/APKEditor)
2. **Decode** it to smali
3. **Patch** the smali — `scripts/patch-ads.sh`
4. **Rebuild** the APK
5. **Sign** it — [uber-apk-signer](https://github.com/patrickfav/uber-apk-signer)
6. **Release** it, tagged `v<version>-noads`

## What gets removed

| Surface | Where it's disabled |
| --- | --- |
| Splash-screen ads (all networks) | `SplashActivity.L2()` → app's own no-ad path |
| In-app banner / native ads | `UnderViewManager.a()` gate forced on |
| App-open / interstitial / resume ads | `GoogleAdManager` (`l0`) methods neutered |
| Cloud & AI subscription popups | auto-dismissed / finished (best-effort) |

Patches anchor on stable Kotlin `.source` names and semantic chokepoints rather
than obfuscated class/method names, and the build fails loudly if a core patch no
longer matches. Full analysis and a version-bump playbook are in
[`docs/ad-removal.md`](docs/ad-removal.md).

## Updating to a new app version

1. Replace the `.xapk` in the repo root with the new version.
2. Commit and push.
3. Grab the APK from the new release once the workflow finishes.

If the run fails, the app's code layout shifted — follow the playbook in
[`docs/ad-removal.md`](docs/ad-removal.md) to re-point the anchors.

## Installing the APK

1. Uninstall the original Yi Home app (signatures differ).
2. Download the APK from the latest [release](../../releases).
3. Allow installs from unknown sources, then install.

## Local build

Requires a JDK and `APKEditor.jar`:

```bash
java -jar APKEditor.jar m -i Yi*.xapk -o merged.apk -f   # merge
java -jar APKEditor.jar d -i merged.apk -o decoded -f     # decode
./scripts/patch-ads.sh decoded                            # patch
java -jar APKEditor.jar b -i decoded -o patched.apk -f    # rebuild (~2 min)
```

Then sign `patched.apk` with uber-apk-signer.

## Disclaimer

For personal, educational use with an app you legitimately own. Not affiliated
with or endorsed by Yi / Kami / Xiaoyi.
